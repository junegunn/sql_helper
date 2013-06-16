# SQLHelper

A simplistic SQL generator (extracted from [jdbc-helper](https://github.com/junegunn/jdbc-helper) gem)

## Installation

Add this line to your application's Gemfile:

    gem 'sql_helper'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install sql_helper

## Example

```ruby
SQLHelper.select(
  prepared: true,
  table:    'mytable',
  project:  %w[a b c d e],
  where: [
    'z <> 100',
    ['y = ?', 200],
    {
      a: "hello 'world'",
      b: (1..10),
      c: (1...10),
      d: ['abc', "'def'"],
      e: { sql: 'sysdate' },
      f: { not: nil },
      g: { gt: 100 },
      h: { lt: 100 },
      i: { like: 'ABC%' },
      j: { not: { like: 'ABC%' } },
      k: { le: { sql: 'sysdate' } },
      l: { ge: 100, le: 200 },
      m: { not: [ 150, { ge: 100, le: 200 } ] },
      n: nil,
      o: { not: (1..10) },
      p: { or: [{ gt: 100 }, { lt: 50 }] },
      q: { like: ['ABC%', 'DEF%'] },
      r: { or: [{ like: ['ABC%', 'DEF%'] }, { not: { like: 'XYZ%' } }] }
    }
  ],
  order: 'a desc',
  limit: 10
)
```
