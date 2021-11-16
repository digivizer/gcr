# GCR

A VCR-like test helper for GRPC clients.

## Example

```ruby
# in some test initializer
GCR.cassette_dir = Rails.root.join("test/fixtures/my_grpc_service")
GCR.stub = MyGRPCServer.stub
```

```ruby
# in your test code
test "MyController#index works" do
  GCR.with_cassette("some cassette name") do
    MyGRPCServer.do_something
  end
end
```

## Configuration

To not save empty requests (for instance when error occur), set `save_empty_requests` as `false`.
```ruby
GCR.save_empty_requests = false
```

## Tests

To run tests:

```
bundle exec rake
```
