use lib 't';
use Test::APIcast::Blackbox 'no_plan';

require("t/http_proxy.pl");

# Can't run twice because one of the test checks the contents of the cache, and
# those change between runs (cache miss in first run, cache hit in second).
repeat_each(1);

run_tests();

__DATA__

=== TEST 1: 3scale backend connection uses proxy
--- env eval
("http_proxy", $ENV{TEST_NGINX_HTTP_PROXY})
--- configuration
{
  "services": [
    {
      "id": 42,
      "backend_version":  1,
      "backend_authentication_type": "service_token",
      "backend_authentication_value": "token-value",
      "proxy": {
        "api_backend": "http://test:$TEST_NGINX_SERVER_PORT/",
        "proxy_rules": [
          { "pattern": "/", "http_method": "GET", "metric_system_name": "hits", "delta": 2 }
        ]
      }
    }
  ]
}
--- backend
  location /transactions/authrep.xml {
    content_by_lua_block {
      local expected = "service_token=token-value&service_id=42&usage%5Bhits%5D=2&user_key=value"
      require('luassert').same(ngx.decode_args(expected), ngx.req.get_uri_args(0))
    }
  }
--- upstream
  location / {
     echo 'yay, api backend: $http_host';
  }
--- request
GET /?user_key=value
--- response_body
yay, api backend: test
--- error_code: 200
--- error_log
apicast cache miss key: 42:value:usage%5Bhits%5D=2
--- no_error_log
[error]

=== TEST 1: upstream API connection uses proxy
--- env eval
("http_proxy", $ENV{TEST_NGINX_HTTP_PROXY})
--- configuration
{
  "services": [
    {
      "id": 42,
      "backend_version":  1,
      "backend_authentication_type": "service_token",
      "backend_authentication_value": "token-value",
      "proxy": {
        "api_backend": "http://test:$TEST_NGINX_SERVER_PORT/",
        "proxy_rules": [
          { "pattern": "/", "http_method": "GET", "metric_system_name": "hits", "delta": 2 }
        ]
      }
    }
  ]
}
--- backend
  location /transactions/authrep.xml {
    content_by_lua_block {
      local expected = "service_token=token-value&service_id=42&usage%5Bhits%5D=2&user_key=value"
      require('luassert').same(ngx.decode_args(expected), ngx.req.get_uri_args(0))
    }
  }
--- upstream
  location / {
     echo 'yay, api backend: $http_host';
  }
--- request
GET /?user_key=value
--- response_body
yay, api backend: test
--- error_code: 200
--- error_log
apicast cache miss key: 42:value:usage%5Bhits%5D=2
--- no_error_log
[error]

=== TEST 1: Upstream Policy connection uses proxy
--- env eval
("http_proxy", $ENV{TEST_NGINX_HTTP_PROXY})
--- configuration
{
  "services": [
    {
      "id": 42,
      "backend_version":  1,
      "backend_authentication_type": "service_token",
      "backend_authentication_value": "token-value",
      "proxy": {
        "api_backend": "http://test:$TEST_NGINX_SERVER_PORT/",
        "proxy_rules": [
          { "pattern": "/", "http_method": "GET", "metric_system_name": "hits", "delta": 2 }
        ]
      }
    }
  ]
}
--- backend
  location /transactions/authrep.xml {
    content_by_lua_block {
      local expected = "service_token=token-value&service_id=42&usage%5Bhits%5D=2&user_key=value"
      require('luassert').same(ngx.decode_args(expected), ngx.req.get_uri_args(0))
    }
  }
--- upstream
  location / {
     echo 'yay, api backend: $http_host';
  }
--- request
GET /?user_key=value
--- response_body
yay, api backend: test
--- error_code: 200
--- error_log
apicast cache miss key: 42:value:usage%5Bhits%5D=2
--- no_error_log
[error]
