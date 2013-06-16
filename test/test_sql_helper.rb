$VERBOSE = true
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'sql_helper'
require 'bigdecimal'
require 'minitest/autorun'

class TestSQLHelper < MiniTest::Unit::TestCase
  def setup
    @conds = [
      'z <> 100',
      ['y = ? or y = ? or y = ?', 200, "Macy's", BigDecimal('3.141592')],
      {
        :a => "hello 'world'",
        :b => (1..10),
        :c => (1...10),
        :d => ['abc', "'def'"],
        :e => { :sql  => 'sysdate' },
        :f => { :not  => nil },
        :g => { :gt   => 100 },
        :h => { :lt   => 100 },
        :i => { :like => 'ABC%' },
        :j => { :not  => { :like => 'ABC%' } },
        :k => { :le   => { :sql => 'sysdate' } },
        :l => { :ge   => 100, :le => 200 },
        :m => { :not  => [ 150, { :ge => 100, :le => 200 } ] },
        :n => nil,
        :o => { :not  => (1..10) },
        :p => { :or   => [{ :gt => 100 }, { :lt => 50 }] },
        :q => { :like => ['ABC%', 'DEF%'] },
        :r => { :or   => [{ :like => ['ABC%', 'DEF%'] }, { :not => { :like => 'XYZ%' } }] },
        :s => { :not  => 100 },
        :t => { :not  => 'str' },
        :u => ('aa'..'zz')
      }
    ]

    @wherep = ["where (z <> 100) and (y = ? or y = ? or y = ?) and a = ? and b between ? and ? and c >= ? and c < ? and (d = ? or d = ?) and e = sysdate and f is not null and g > ? and h < ? and i like ? and not j like ? and k <= sysdate and l >= ? and l <= ? and not (m = ? or m >= ? and m <= ?) and n is null and not o between ? and ? and (p > ? or p < ?) and (q like ? or q like ?) and ((r like ? or r like ?) or not r like ?) and s <> ? and t <> ? and u between ? and ?",
      200, "Macy's", BigDecimal("3.141592"),
      "hello 'world'",
      1, 10,
      1, 10,
      'abc', "'def'",
      100,
      100,
      'ABC%',
      'ABC%',
      100, 200,
      150, 100, 200,
      1, 10,
      100, 50,
      'ABC%', 'DEF%',
      'ABC%', 'DEF%', 'XYZ%',
      100,
      'str',
      'aa', 'zz'
    ]

    @where = @wherep[0]
    @wherep[1..-1].each do |param|
      @where = @where.sub('?', SQLHelper.quote(param))
    end
  end

  def test_where
    assert_equal @where, SQLHelper.where(*@conds)
  end

  def test_where_prepared
    assert_equal @wherep, SQLHelper.where_prepared(*@conds)
  end

  def test_select
    sql, *params = SQLHelper.select(
      :prepared => true,
      :project  => [:a, :b, :c],
      :table    => :mytable,
      :top      => 10,
      :where    => @conds,
      :order    => 'a desc',
      :limit    => 100
    )
    assert_equal "select top 10 a, b, c from mytable #{@wherep[0]} order by a desc limit 100", sql
    assert_equal @wherep[1..-1], params

    sql, *params = SQLHelper.select(
      :prepared => true,
      :project  => '*',
      :table    => 'mytable',
      :where    => @conds,
      :order    => ['a desc', 'b asc'],
      :limit    => [100, 300]
    )
    assert_equal "select * from mytable #{@wherep[0]} order by a desc, b asc limit 100, 300", sql
    assert_equal @wherep[1..-1], params
  end

  def test_count
    sql, *params = SQLHelper.count(
      :prepared => true,
      :table     => :mytable,
      :where    => @conds
    )
    assert_equal "select count(*) from mytable #{@wherep[0]}", sql
    assert_equal @wherep[1..-1], params
    assert_equal "select count(*) from mytable where a is not null",
      SQLHelper.count(:prepared => false, :table => :mytable, :where => { :a => { :not => nil } })
  end

  def test_insert
    [:insert, :insert_ignore, :replace].each do |m|
      sql, *binds = SQLHelper.send(m,
        :table => :mytable,
        :data => { :a => 100, :b => 200, :c => { :sql => 'sysdate' }, :d => "hello 'world'" },
        :prepared => true
      )
      assert_equal %[#{m.to_s.gsub '_', ' '} into mytable (a, b, c, d) values (?, ?, sysdate, ?)], sql
      assert_equal [100, 200, "hello 'world'"], binds

      sql = SQLHelper.send(m,
        :table => :mytable,
        :data => { :a => 100, :b => 200, :c => { :sql => 'sysdate' }, :d => "hello 'world'" },
        :prepared => false
      )
      assert_equal %[#{m.to_s.gsub '_', ' '} into mytable (a, b, c, d) values (100, 200, sysdate, 'hello ''world''')], sql
    end
  end

  def test_delete
    del = SQLHelper.delete(:table => 'mytable', :where => @conds, :prepared => true)
    assert_equal "delete from mytable #{@wherep.first}", del.first
    assert_equal @wherep[1..-1], del[1..-1]

    assert_equal "delete from mytable #{@where}",
      SQLHelper.delete(:table => :mytable, :where => @conds, :prepared => false)
  end

  def test_update
    data = { :a => 100, :b => 200, :c => { :sql => 'sysdate' }, :d => "hello 'world'" }
    sql, *binds = SQLHelper.update(:table => :mytable, :data => data, :where => @conds, :prepared => true)

    assert_equal "update mytable set a = ?, b = ?, c = sysdate, d = ? #{@wherep.first}", sql
    assert_equal [100, 200, "hello 'world'"] + @wherep[1..-1], binds

    sql = SQLHelper.update(:table => :mytable, :data => data, :where => @conds, :prepared => false)
    assert_equal "update mytable set a = 100, b = 200, c = sysdate, d = 'hello ''world''' #{@where}", sql
  end

  def test_check
    [
      %['hello],
      %['hell'o'],
      %[hel--lo],
      %[hel;lo],
      %[hel/*lo],
      %[hel*/lo],
    ].each do |sql|
      assert_raises(SyntaxError) { SQLHelper.check sql }
    end
  end
end
