# Azure Service Bus

Connect to Azure Service bus via HTTP, because Microsoft has officially stopped supporting Azure SDK for Ruby

## Usage

1. Install deps: `gem install bundler && bundle install`.
2. Set the following environment variables
  * `SB_NAMESPACE` : Usually the first part before `servicebus.windows.net`
  * `QUEUE_NAME` : Default value `test_queue`
  * `SAS_NAME` : Default value `RootManageSharedAccessKey`
  * `SAS_VALUE` : Primary (or Secondary) key. Looks like long garbled string 😄
  * `LOGLEVEL` : Default value `DEBUG`
3. Run `bundle exec rake test` to run the tests, or `bundle exec rake run` to run the program.
