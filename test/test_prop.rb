require 'helper'

class TestProp < Test::Unit::TestCase

  context "Prop" do
    setup do
      @store = {}
      Prop.read  { |key| @store[key] }
      Prop.write { |key, value| @store[key] = value }

      @start = Time.now
      Time.stubs(:now).returns(@start)
    end

    {"with incrementer" => lambda { Prop.increment { |key, inc| @store[key] ? @store[key] += inc : @store[key] = inc } },
     "without incrementer" => lambda {} }.each do |desc, setup_block_for_context|
       context desc do
         setup do
           instance_eval(&setup_block_for_context)
         end

         teardown do
           Prop.instance_variable_set("@incrementer", nil)
         end

         context "#defaults" do
          should "raise errors on invalid configuation" do
            assert_raises(RuntimeError) do
              Prop.defaults :hello_there, :threshold => 20, :interval => 'hello'
            end

            assert_raises(RuntimeError) do
              Prop.defaults :hello_there, :threshold => 'wibble', :interval => 100
            end
          end

          should "result in a default handle" do
            Prop.defaults :hello_there, :threshold => 4, :interval => 10
            4.times do |i|
              assert_equal (i + 1), Prop.throttle!(:hello_there, 'some key')
            end

            assert_raises(Prop::RateLimitExceededError) { Prop.throttle!(:hello_there, 'some key') }
            assert_equal 5, Prop.throttle!(:hello_there, 'some key', :threshold => 20)
          end

          should "create a handle accepts various cache key types" do
            Prop.defaults :hello_there, :threshold => 4, :interval => 10
            assert_equal 1, Prop.throttle!(:hello_there, 5)
            assert_equal 2, Prop.throttle!(:hello_there, 5)
            assert_equal 1, Prop.throttle!(:hello_there, '6')
            assert_equal 2, Prop.throttle!(:hello_there, '6')
            assert_equal 1, Prop.throttle!(:hello_there, [ 5, '6' ])
            assert_equal 2, Prop.throttle!(:hello_there, [ 5, '6' ])
          end
        end

        context "#reset" do
          setup do
            Prop.defaults :hello, :threshold => 10, :interval => 10

            5.times do |i|
              assert_equal (i + 1), Prop.throttle!(:hello)
            end
          end

          should "set the correct counter to 0" do
            Prop.throttle!(:hello, 'wibble')
            Prop.throttle!(:hello, 'wibble')

            Prop.reset(:hello)
            assert_equal 1, Prop.throttle!(:hello)

            assert_equal 3, Prop.throttle!(:hello, 'wibble')
            Prop.reset(:hello, 'wibble')
            assert_equal 1, Prop.throttle!(:hello, 'wibble')
          end
        end

        context "#throttled?" do
          should "return true once the threshold has been reached" do
            Prop.defaults(:hello, :threshold => 2, :interval => 10)
            Prop.throttle!(:hello)
            assert !Prop.throttled?(:hello)
            Prop.throttle!(:hello)
            assert Prop.throttled?(:hello)
          end
        end

        context "#throttle!" do
          should "increment counter correctly" do
            3.times do |i|
              assert_equal (i + 1), Prop.throttle!(:hello, nil, :threshold => 10, :interval => 10)
            end
          end

          should "reset counter when time window is passed" do
            3.times do |i|
              assert_equal (i + 1), Prop.throttle!(:hello, nil, :threshold => 10, :interval => 10)
            end

            Time.stubs(:now).returns(@start + 20)

            3.times do |i|
              assert_equal (i + 1), Prop.throttle!(:hello, nil, :threshold => 10, :interval => 10)
            end
          end

          should "not increment the counter beyond the threshold" do
            Prop.defaults(:hello, :threshold => 5, :interval => 1)
            10.times do |i|
              Prop.throttle!(:hello) rescue nil
            end

            assert_equal 5, Prop.query(:hello)
          end

          should "support custom increments" do
            Prop.defaults(:hello, :threshold => 100, :interval => 10)

            Prop.throttle!(:hello)
            Prop.throttle!(:hello)

            assert_equal 2, Prop.query(:hello)

            Prop.throttle!(:hello, nil, :increment => 48)

            assert_equal 50, Prop.query(:hello)
          end

          should "raise Prop::RateLimitExceededError when the threshold is exceeded" do
            5.times do |i|
              Prop.throttle!(:hello, nil, :threshold => 5, :interval => 10)
            end
            assert_raises(Prop::RateLimitExceededError) do
              Prop.throttle!(:hello, nil, :threshold => 5, :interval => 10)
            end

            begin
              Prop.throttle!(:hello, nil, :threshold => 5, :interval => 10)
              fail
            rescue Prop::RateLimitExceededError => e
              assert_equal :hello, e.handle
              assert_equal "hello threshold of 5 exceeded for key ''", e.message
              assert e.retry_after
            end
          end
        end
      end
    end
  end
end
