local named_args = require('apicast.policy.url_rewriting.named_args')

describe('named_args', function()
  describe('.replace', function()
    describe('when there is a match', function()
      describe('and there is a query params part in the "replace" arg', function()
        it('returns the new path and the list of args', function()
          local path = '/abc/def/ghi/jkl'
          local match_rule = '/{var_1}/{var_2}/{var_3}/{var_4}'
          local replace = '/{var_3}/{var_4}?{var_1}=1&{var_2}=2'

          local new_path, new_args = named_args.replace(path, match_rule, replace)

          assert.equals('/ghi/jkl', new_path)
          assert.same({ abc = '1', def = '2' }, new_args)
        end)
      end)

      describe('and there is not a query params part in the "replace" arg', function()
        it('returns the new path and an empty list of args', function()
          local path = '/abc/def/ghi/jkl'
          local match_rule = '/{var_1}/{var_2}/{var_3}/{var_4}'
          local replace = '/{var_3}/{var_4}/{var_1}/{var_2}'

          local new_path, new_args = named_args.replace(path, match_rule, replace)

          assert.equals('/ghi/jkl/abc/def', new_path)
          assert.same({}, new_args)
        end)
      end)
    end)

    describe('when there is not a match', function()
      it('returns the original path and an empty list of args', function()
        local path = '/abc'
        local match_rule = '/{var_1}/{var_2}/{var_3}/{var_4}'
        local replace = '/{var_3}/{var_4}/{var_1}/{var_2}'

        local new_path, new_args = named_args.replace(path, match_rule, replace)

        assert.equals('/abc', new_path)
        assert.same({}, new_args)
      end)
    end)
  end)
end)
