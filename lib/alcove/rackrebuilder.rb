
if Kernel.const_defined?(:Rack)

    class Alcove::RackRebuilder
        def initialize(app, builder)
            @builder = builder
            @app = Rack::Cascade.new([
                Proc.new do |env|
                    unless builder.uptodate?
                        $stderr.puts "Rebuilding"
                        builder.clean
                        builder.build 
                    end
                    [404]
                end,
                app
            ])
        end

        def call(e)
            return @app.call(e)
        end
    end

end
