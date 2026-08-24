require 'pathname'

module CocoapodsSourceFix
  # 单条替换规则
  #
  # 目标定位（互斥，均不指定则为全局）：
  #   pod:   'SomePod'        → 定位到 installer.sandbox.pod_dir('SomePod')，glob 相对该 Pod 目录
  #   dir:   'path'            → 目录，路径绝对则直接使用，相对则相对 Podfile 目录
  #   file:  'path'            → 文件，路径绝对则直接使用，相对则相对 Podfile 目录
  #   （无以上字段）           → 全局，glob 相对 Podfile 目录（如 'Pods/**/*.{h,m}'）
  #
  # 替换内容（至少一组）：
  #   from/to 单组字面量替换；pairs 多组替换；均可选 regex: true 启用正则
  #
  # 排除（可选）：
  #   exclude: '模式' 或 ['模式1', '模式2']，glob 模式，基准与 glob 相同
  #   （pod → Pod 目录；dir → 目标目录；全局 → Podfile 目录），命中文件不修复
  class Rule
    attr_reader :name, :target_type, :target, :glob, :replaces, :enabled, :excludes

    def initialize(raw, base_dir:)
      @raw = raw || {}
      @base_dir = base_dir
      @name = @raw['name']
      @glob = @raw['glob']
      @enabled = @raw.fetch('enabled', true)
      @excludes = Array(@raw['exclude']).compact.map(&:to_s)
      @replaces = parse_replaces
      resolve_target
    end

    def enabled?
      @enabled
    end

    def label
      @name || "target=#{@target_type}#{@target ? "(#{@target})" : ''}"
    end

    private

    def parse_replaces
      list = []
      if @raw['from'] && @raw['to']
        list << build_replace(@raw['from'], @raw['to'], @raw.fetch('regex', false))
      end
      Array(@raw['pairs']).each do |pair|
        list << build_replace(pair['from'], pair['to'], pair.fetch('regex', false))
      end
      list
    end

    def build_replace(from, to, regex)
      { from: from, to: to, regex: regex }
    end

    def resolve_target
      if @raw['pod']
        @target_type = :pod
        @target = @raw['pod']
      elsif @raw['dir']
        @target_type = :dir
        @target = @raw['dir']
      elsif @raw['file']
        @target_type = :file
        @target = @raw['file']
      else
        @target_type = :global
      end
    end
  end
end
