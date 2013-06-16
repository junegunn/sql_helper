require "sql_helper/version"
require 'set'
require 'bigdecimal'

module SQLHelper
  class << self
    def escape arg
      arg.to_s.gsub("'", "''")
    end

    # A naive check
    def check expr
      expr = expr.to_s
      test = expr.to_s.gsub(/(['`"]).*?\1/, '').
                       gsub(%r{/\*.*?\*/}, '').
                       strip
      raise SyntaxError.new("cannot contain unquoted semi-colons: #{expr}") if test.include?(';')
      raise SyntaxError.new("cannot contain unquoted comments: #{expr}") if test.match(%r{--|/\*|\*/})
      raise SyntaxError.new("unclosed quotation mark: #{expr}") if test.match(/['"`]/)
      raise SyntaxError.new("empty expression") if expr.strip.empty?
      expr
    end

    def quote arg
      case arg
      when String, Symbol
        "'#{arg.to_s.gsub "'", "''"}'"
      when BigDecimal
        arg.to_s('F')
      when nil
        'null'
      else
        if expr?(arg)
          arg.values.first
        else
          arg.to_s
        end
      end
    end

    def insert arg
      insert_internal 'insert into', arg
    end

    def insert_ignore arg
      insert_internal 'insert ignore into', arg
    end

    def replace arg
      insert_internal 'replace into', arg
    end

    def delete args
      check_keys args, Set[:table, :where, :prepared]

      wc, *wp = where_internal args[:prepared], args[:where]
      sql = "delete from #{args.fetch :table} #{wc}".strip
      if args[:prepared]
        [sql, *wp]
      else
        sql
      end
    end

    def update args
      check_keys args, Set[:prepared, :where, :table, :data]
      table    = args.fetch(:table)
      data     = args.fetch(:data)
      prepared = args[:prepared]
      where,
        *wbind = where_internal(args[:prepared], args[:where])
      bind     = []
      vals     = data.map { |k, v|
        if prepared
          if expr?(v)
            [k, v.values.first].join(' = ')
          else
            bind << v
            "#{k} = ?"
          end
        else
          [k, quote(v)].join(' = ')
        end
      }
      sql = "update #{check table} set #{vals.join ', '} #{where}".strip
      if prepared
        [sql] + bind + wbind
      else
        sql
      end
    end

    def count args
      check_keys args, Set[:prepared, :where, :table]
      select args.merge(:project => 'count(*)')
    end

    def select args
      check_keys args, Set[:prepared, :project, :where, :order, :limit, :top, :table]

      top       = args[:top] ? "top #{args[:top]}" : ''
      project   = project(*args[:project])
      where,
        *params = args[:where] ? where_internal(args[:prepared], args[:where]) : ['']
      order     = order(*args[:order])
      limit     = limit(*args[:limit])

      sql = ['select', top, project, 'from', args.fetch(:table),
             where, order, limit].reject(&:empty?).join(' ')
      if args[:prepared]
        [ sql, *params ]
      else
        sql
      end
    end

    def project *args
      args = args.compact.map(&:to_s).map(&:strip).reject(&:empty?)
      if args.empty?
        '*'
      else
        check args.join ', '
      end
    end

    def order *args
      args = args.compact.map(&:to_s).map(&:strip).reject(&:empty?)
      if args.empty?
        ''
      else
        check "order by #{args.join ', '}"
      end
    end

    def limit *args
      limit, offset = args.reverse.map { |e|
        s = e.to_s.strip
        s.empty? ? nil : s
      }
      arg = arg.to_s.strip
      if offset
        check "limit #{offset}, #{limit}"
      elsif limit
        check "limit #{limit}"
      else
        ''
      end
    end

    def where *conds
      where_internal false, conds
    end

    def where_prepared *conds
      where_internal true, conds
    end

  private
    OPERATOR_MAP = {
      :gt   => '>',
      :ge   => '>=',
      :lt   => '<',
      :le   => '<=',
      :ne   => '<>',
      :>    => '>',
      :>=   => '>=',
      :<    => '>',
      :<=   => '>=',
      :like => 'like'
    }

    def expr? val
      val.is_a?(Hash) && val.length == 1 && [:sql, :expr].include?(val.keys.first)
    end

    def check_keys args, known
      raise ArgumentError, "hash expected" unless args.is_a?(Hash)
      unknown = Set.new(args.keys) - known
      raise ArgumentError, "unknown keys: #{unknown.to_a.join ', '}" unless unknown.empty?
    end

    def where_internal prepared, conds
      sqls   = []
      params = []

      conds =
        case conds
        when String, Hash
          [conds]
        when nil
          []
        when Array
          conds
        else
          raise ArgumentError, "invalid argument type: #{conds.class}"
        end

      conds.each do |cond|
        next if cond.nil? || cond.empty?
        case cond
        when String
          sql = cond.strip
          next if sql.empty?
          sqls << "(#{sql})"
        when Array
          sql = cond[0].to_s.strip
          next if sql.empty?
          if prepared
            sqls << "(#{cond[0]})"
            params += cond[1..-1]
          else
            params = cond[1..-1]
            sql = "(#{cond[0]})".gsub('?') {
              if params.empty?
                '?'
              else
                quote params.shift
              end
            }
            sqls << sql
          end
        when Hash
          cond.each do |col, cnd|
            ret = eval_hash_cond col, cnd, prepared
            sqls << ret[0]
            params += ret[1..-1] || []
          end
        end
      end

      if prepared
        sqls.empty? ? [''] : ["where #{sqls.join ' and '}"].concat(params)
      else
        sqls.empty? ? '' : "where #{sqls.join ' and '}"
      end
    end

    def eval_hash_cond col, cnd, prepared
      case cnd
      when Numeric, String
        prepared ? ["#{col} = ?", cnd] : [[col, quote(cnd)].join(' = ')]
      when Range
        if cnd.exclude_end?
          prepared ?
            ["#{col} >= ? and #{col} < ?", cnd.begin, cnd.end] :
            ["#{col} >= #{quote cnd.begin} and #{col} < #{quote cnd.end}"]
        else
          prepared ?
            ["#{col} between ? and ?", cnd.begin, cnd.end] :
            ["#{col} between #{quote cnd.begin} and #{quote cnd.end}"]
        end
      when Array
        sqls   = []
        params = []
        cnd.each do |v|
          ret = eval_hash_cond col, v, prepared
          sqls << ret[0]
          params += ret[1..-1]
        end
        ["(#{sqls.join(' or ')})", *params]
      when nil
        ["#{col} is null"]
      when Hash
        rets = cnd.map { |op, val|
          case op
          when :expr, :sql
            ["#{col} = #{check val}"]
          when :not
            case val
            when nil
              ["#{col} is not null"]
            when String, Numeric
              prepared ?
                ["#{col} <> ?", val] :
                ["#{col} <> #{quote val}"]
            else
              ary = eval_hash_cond col, val, prepared
              ary[0].prepend 'not '
              ary
            end
          when :or
            sqls   = []
            params = []
            val.each do |v|
              ret = eval_hash_cond col, v, prepared
              sqls << ret[0]
              params += ret[1..-1]
            end
            ["(#{sqls.join(' or ')})", *params]
          when :gt, :>, :ge, :>=, :lt, :<, :le, :<=, :ne, :like
            if val.is_a?(Hash)
              if expr?(val)
                [[col, OPERATOR_MAP[op], check(val.values.first)].join(' ')]
              else
                raise ArgumentError, "invalid condition"
              end
            elsif val.is_a?(Array)
              prepared ?
                ["(#{(["#{col} #{OPERATOR_MAP[op]} ?"] * val.length).join(' or ')})", *val] :
                ["(#{val.map { |v| [col, OPERATOR_MAP[op], quote(v)].join ' ' }.join(' or ')})"]
            else
              prepared ?
                ["#{col} #{OPERATOR_MAP[op]} ?", val] :
                [[col, OPERATOR_MAP[op], quote(val)].join(' ')]
            end
          else
            raise ArgumentError, "unexpected operator: #{op}"
          end
        }
        [rets.map(&:first).join(' and '), *rets.inject([]) { |prms, r| prms.concat r[1..-1] }]
      else
        raise ArgumentError, "invalid condition: #{cnd}"
      end
    end

    def insert_internal prefix, args
      check_keys args, Set[:table, :data, :prepared]
      prep = args[:prepared]
      into = args.fetch(:table)
      data = args.fetch(:data)

      bind = []
      cols = data.keys
      vals = data.values.map { |val|
        if prep
          if expr?(val)
            val.values.first
          else
            bind << val
            '?'
          end
        else
          quote(val)
        end
      }

      sql = "#{prefix} #{into} (#{cols.join ', '}) values (#{vals.join ', '})"
      if args[:prepared]
        [sql] + bind
      else
        sql
      end
    end
  end
end
