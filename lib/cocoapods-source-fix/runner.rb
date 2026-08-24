require 'fileutils'
require 'cocoapods-source-fix/logger'

module CocoapodsSourceFix
  # 执行替换：收集目标文件 → 逐文件替换 → 幂等写回 → 日志输出
  class Runner
    def initialize(context, config, podfile_dir: nil)
      @context = context
      @config = config
      @podfile_dir = podfile_dir || default_podfile_dir
    end

    def run
      Logger.info "patching source files..."
      fixed_total = 0
      skipped_total = 0
      @config.rules.each do |rule|
        next unless rule.enabled?

        files = collect_files(rule)
        fixed, skipped = process_rule(rule, files)
        fixed_total += fixed
        skipped_total += skipped
      end
      Logger.info "finished patching source files (#{fixed_total} fixed, #{skipped_total} skipped)"
    end

    private

    # 按目标类型收集待处理文件（含 exclude 过滤）
    def collect_files(rule)
      base_dir, files = files_for_target(rule)
      apply_excludes(files, rule, base_dir)
    end

    def files_for_target(rule)
      case rule.target_type
      when :pod
        dir = @context.sandbox.pod_dir(rule.target).to_s
        [dir, glob_files(dir, rule.glob || '**/*')]
      when :dir
        dir = resolve_path(rule.target)
        [dir, glob_files(dir, rule.glob || '**/*')]
      when :file
        path = resolve_path(rule.target)
        [File.dirname(path), File.file?(path) ? [path] : []]
      when :global
        [@podfile_dir, glob_files(@podfile_dir, rule.glob || '**/*')]
      end
    end

    # exclude 为 glob 模式，基准与 glob 相同（相对规则目标目录）。
    # 注意：模式以 /** 结尾时 fnmatch 只匹配一层，追加 /**/* 变体覆盖整棵目录树。
    def apply_excludes(files, rule, base_dir)
      return files if rule.excludes.empty?

      patterns = rule.excludes.flat_map do |pattern|
        if pattern == '**' || pattern.end_with?('/**')
          [pattern, File.join(pattern, '*')]
        else
          [pattern]
        end
      end
      flags = File::FNM_PATHNAME | File::FNM_EXTGLOB

      files.reject do |file|
        rel = file.delete_prefix(base_dir + '/')
        hit = patterns.any? { |p| File.fnmatch(p, rel, flags) }
        Logger.info "    🚫 已排除：#{file}" if hit && @config.verbose
        hit
      end
    end

    # 兜底：优先全局 Pod::Config 中的 Podfile，其次 sandbox_root 上级，最后 Dir.pwd
    def default_podfile_dir
      if defined?(Pod::Config) && Pod::Config.instance.respond_to?(:podfile)
        pf = Pod::Config.instance.podfile
        if pf && pf.respond_to?(:defined_in_file) && pf.defined_in_file
          return File.dirname(pf.defined_in_file.to_s)
        end
      end
      if @context.respond_to?(:sandbox_root) && @context.sandbox_root
        return File.dirname(@context.sandbox_root)
      end
      Dir.pwd
    end

    def glob_files(dir, glob)
      return [] unless File.directory?(dir)

      Dir.glob(File.join(dir, glob)).select { |f| File.file?(f) }
    end

    # 绝对路径直接使用；相对路径以 Podfile 目录为基准
    def resolve_path(path)
      p = Pathname.new(path)
      p.absolute? ? path : File.expand_path(path, @podfile_dir)
    end

    # 返回 [fixed, skipped]：fixed 为实际写入的文件数，skipped 为内容已是最新（无变化）的文件数
    def process_rule(rule, files)
      Logger.info "  processing rule: #{rule.label}"
      if files.empty?
        Logger.info "    ⏭️ 跳过（无匹配文件）"
        return [0, 0]
      end

      touched = 0
      skipped = 0
      files.each do |file|
        begin
          content = File.read(file)
        rescue StandardError => e
          Logger.info "    ⚠️ 读取失败：#{file}（#{e.message}）"
          next
        end

        new_content = rule.replaces.reduce(content) { |acc, rep| apply_replace(acc, rep) }
        if new_content == content # 幂等：无变化跳过写文件
          skipped += 1
          Logger.info "    ⏭️ 已是最新：#{file}" if @config.verbose
          next
        end

        FileUtils.chmod 0644, file
        File.write(file, new_content)
        Logger.info "    ✅ 已修复文件：#{file}"
        touched += 1
      end
      if touched.zero?
        Logger.info "    ⏭️ 跳过（#{skipped} 个文件内容已是最新，无需修复）"
      elsif skipped.positive?
        Logger.info "    ✅ 修复完成（#{touched} 个文件；#{skipped} 个已是最新）"
      end
      [touched, skipped]
    end

    def apply_replace(content, rep)
      # 必须显式构造 Regexp：Ruby 3.x 下 gsub(字符串) 不会把字符串当正则源码解析
      pattern = if rep[:regex]
                  Regexp.new(rep[:from])
                else
                  # 默认字面量替换，避免被当作正则元字符
                  Regexp.new(Regexp.escape(rep[:from]))
                end
      # block 形式传 replacement，避免 \1 等被解释为捕获组引用
      content.gsub(pattern) { rep[:to] }
    end
  end
end
