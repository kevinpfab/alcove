
require "fileutils"
require "find"
require "json"
require "juicer"
require "less"
require "yaml"
require "zlib"

module Alcove 
    class Builder
        BASEDIR = File.realpath(File.join(File.dirname(__FILE__), "..", ".."))

        JSDIR   = File.join(BASEDIR, "js")
        HTMLDIR = File.join(BASEDIR, "html")

        FRAMEWORK = IO.read(File.join(JSDIR, "framework.js"))
        WRAPPER   = IO.read(File.join(JSDIR, "wrapper.js"))

        JS_DEPENDENCIES = File.join(BASEDIR, "js", "dependencies")

        TEST_FILE  = IO.read(File.join(HTMLDIR, "test_file.html"))
        TEST_INDEX = IO.read(File.join(HTMLDIR, "test_index.html"))
        TEST_LANG  = IO.read(File.join(HTMLDIR, "test_lang.html"))
        TEST_LINK  = IO.read(File.join(HTMLDIR, "test_link.html"))
        TEST_LIST  = IO.read(File.join(HTMLDIR, "test_list.html"))

        DEFAULTS = {
            :common_less  => "style/common",
            :js           => "js",
            :locale       => "locale",
            :output       => "output",
            :style        => "style",
            :static       => "static",
            :test_output  => "output/test",
            :widget_tests => "test/widgets",
            :widgets      => "widgets",
        }

        # {{{ initialize
        def initialize(basedir, opts = nil)
            @basedir = basedir
            if opts.nil?
                config_file = File.join(basedir, 'alcove.yaml')
                opts = {}
                if File.exists?(config_file)
                    opts = YAML.load_file(config_file)
                    opts = opts.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
                end               
            end
            @opts = DEFAULTS.merge(opts)

            @dirs = {}
            @opts.each do |k,v|
                @dirs[k] = File.join(basedir, v)
            end
        end

        # }}}
        # {{{ clean
        def clean
            FileUtils.remove_dir(@dirs[:output]) if File.exists?(@dirs[:output])
            FileUtils.mkdir_p(@dirs[:output])
        end

        # }}}
        # {{{ build
        def build(finalize = false)
            FileUtils.mkdir_p(@dirs[:output]) if !File.exists?(@dirs[:output])
            static()
            js(finalize)
            css(finalize)
        end

        # }}}
        # {{{ build_test
        def build_test(widget)
            build(false)
            FileUtils.mkdir_p(@dirs[:test_output]) if !File.exists?(@dirs[:test_output])
            return test(widget)
        end

        # }}}
        # {{{ new_app
        # def new_app
        def new_app(name)
            app_dir = File.join(@basedir, name)
            FileUtils.mkdir_p(app_dir) if !File.exists?(app_dir)

            @opts.each do |k,v|
                dir = File.join(@basedir, name, v)
                FileUtils.mkdir_p(dir) if !File.exists?(dir)
            end

            install_dependencies
        end

        # }}}
        # {{{ install_dependencies
        def install_dependencies
            Dir.chdir(JS_DEPENDENCIES) do
                Dir.glob("*").each do |file|
                    FileUtils.cp_r(file, File.join(@dirs[:js], file))
                end
            end
        end

        # }}}
        # {{{ uptodate?
        def uptodate?
            newest_src = Time.at(0)
            @dirs.each do |name, dir|
                next if name == :output || name == :test_output
                Find.find(dir) do |file|
                    unless File::directory? file
                        newest_src = [newest_src, File.new(file).mtime].max
                    end
                end
            end

            oldest_built = nil
            Find.find(@dirs[:output]) do |file|
                unless File::directory? file
                    if oldest_built.nil?
                        oldest_built = Time.now            
                    end
                    oldest_built = [oldest_built, File.new(file).mtime].min
                end
            end

            return !oldest_built.nil? && oldest_built.to_i >= newest_src.to_i
        end

        # }}}

        protected
        # {{{ css
        def css(finalize = false)
            common = Dir.glob(@dirs[:common_less] + "/**/*.less").map{|file|
                IO.read(file)
            }.join("\n").strip + "\n"
            files = (Dir.glob(@dirs[:style] + "/*.css") + Dir.glob(@dirs[:style] + "/*.less"))
            embedder = Juicer::ImageEmbed.new :document_root => @dirs[:output], :type => :data_uri
            files.each do |file|
                content = common + IO.read(file)
                begin
                    content = Less::Parser.new({
                        :paths => [@dirs[:style]],
                    }).parse(content).to_css({:compress => finalize})
                rescue Exception => e
                    temp = File.join(@dirs[:output], "__temp.less")
                    File.open(temp, 'w') do |f|
                        f.puts content
                    end
                    raise [
                        "Less Exception processing #{file} - content saved to #{temp}",
                        e.message,
                        e.backtrace,
                    ].flatten.join("\n")
                end

                target = File.join(@dirs[:output], File.basename(file, File.extname(file)) + ".css")
                File.open(target, "w") do |output|
                    output.puts content
                end
                embedder.save(target)
            end
        end

        # }}}
        # {{{ js
        def js(finalize = false)
            scripts = Dir.glob(@dirs[:js] + "/**/*.js").sort.partition{|f|
                start = File.basename(f)[0]
                start.downcase == start
            }

            locales.each do |lang, lang_file|
                target = File.join(@dirs[:output], "compiled.#{lang}.js")
                File.open(target, "w") do |output|
                    output.puts(scripts[0].map{|script| IO.read(script)}.join("\n"))
                    output.puts(FRAMEWORK);
                    output.puts("Alcove.TEXT = " + IO.read(lang_file) + ";")
                    output.puts(scripts[1].map{|script| IO.read(script)}.join("\n"))
                    output.puts(widgets)
                end

                if finalize
                    installer = Juicer::Install::YuiCompressorInstaller.new
                    installer.install rescue Exception
                    yuid = File.join([installer.install_dir, installer.path, "bin"])
                    yuic = Juicer::Minifyer::YuiCompressor.new(:bin_path => yuid)
                    yuic.save(target)

                    Zlib::GzipWriter.open(target + "z") do |gz|
                        gz.write IO.read(target)
                    end
                end
            end
        end

        # }}}
        # {{{ locales
        def locales
            lang_files = Dir.glob(@dirs[:locale] + "/*.js").sort
            return Hash[*(lang_files.map{|file|
                name = File.basename(file, File.extname(file))
                next [name, file]
            }.flatten)]
        end

        # }}}
        # {{{ static
        def static
            dir = @dirs[:static]
            Dir.chdir(@dirs[:static]) do
                Dir.glob("*").each do |file|
                    FileUtils.cp_r(file, File.join(@dirs[:output], file))
                end
            end
        end

        # }}}
        # {{{ test
        def test(widget)
            source_file = File.join(@dirs[:widgets], *widget.split("."), "source.js")
            raise("Unknown widget #{widget}") if !File.exists?(source_file)
            test_dir = File.join(@dirs[:widget_tests], *widget.split("."))
            raise("Widget test dir #{test_dir} does not exist") if !File.exists?(test_dir)
            test_files = Dir.glob(File.join(test_dir, "*.js"))
            raise("Widget has no test_files in #{test_dir}") if test_files.length == 0

            languages = locales.keys
            lang_links = []
            languages.each do |lang|
                orig_css = File.join(@dirs[:output], "style.css") 
                css = File.join(@dirs[:test_output], "style.css") 

                orig_js  = File.join(@dirs[:output], "compiled.#{lang}.js") 
                js  = File.join(@dirs[:test_output], "compiled.#{lang}.js") 



                FileUtils.cp(orig_css, css) if File.exists?(orig_css)
                FileUtils.cp(orig_js, js)

                data = Hash[*(test_files.map{|test_file|
                    name = File.basename(test_file, File.extname(test_file))

                    source = IO.read(test_file).strip

                    code = TEST_FILE.gsub(/\$\$[A-Z]*?\$\$/, {
                        "$$BODY$$"    => source,
                        "$$CSSFILE$$" => File.basename(css),
                        "$$JSFILE$$"  => File.basename(js),
                        "$$NAME$$"    => name,
                    })

                    filename = "test_%s.#{lang}.html" % name
                    target = File.join(@dirs[:test_output], filename)
                    File.open(target, "w") do |file|
                        file.puts(code)
                    end

                    next [name, filename]
                }.flatten)]

                links = data.map{|name,file|
                    next TEST_LINK.gsub(/\$\$[A-Z]*?\$\$/, {
                        "$$NAME$$" => name,
                        "$$FILE$$" => file,
                    })
                }.join("\n")

                target = File.join(@dirs[:test_output], "index.#{lang}.html")
                File.open(target, "w") do |file|
                    file.puts TEST_LIST.gsub(/\$\$[A-Z]*?\$\$/, {
                        "$$LINKS$$" => links,
                    })
                end
                lang_links.push TEST_LANG.gsub(/\$\$[A-Z]*?\$\$/, {
                    "$$NAME$$" => lang,
                    "$$FILE$$" => "index.#{lang}.html",
                })
            end

            target = File.join(@dirs[:test_output], "index.html")
            File.open(target, "w") do |file|
                file.puts TEST_INDEX.gsub(/\$\$[A-Z]*?\$\$/, {
                    "$$LINKS$$" => lang_links.join("\n"),
                })
            end
            return File.dirname(target)
        end

        # }}}
        # {{{ widgets
        def widgets
            result = Dir.glob(@dirs[:widgets] + "/**/source.js").sort{|a,b|
                next File.dirname(a) <=> File.dirname(b)
            }.map{|file|
                dir = File.dirname(file)

                name = dir[@dirs[:widgets].length+1..-1].gsub("/", ".")
                source = IO.read(file).strip

                # Convert "method" to assignments
                args = []
                source.gsub!(/^return\s*function\s*\((.*?)\)\s*\{(.*)\};$/m) do |match|
                    $1.split(",").each do |arg|
                        args.push arg.strip
                    end
                    next $2
                end
                len = args.length;
                args = args.map.with_index{|arg, idx| "var #{arg} = args[#{idx}];"}.push(
                    "var $$callbacks = args[#{len}] || {};"
                ).join("\n")
                source = args + source

                static_file = File.join(dir, "static.js")
                static = IO.read(static_file) if File.exists? static_file

                templates = "{%s}" % Dir.glob(dir + "/*.html").map{|html|
                    tname = File.basename(html, File.extname(html)).to_json
                    content = IO.read(html)
                        .gsub("\n", "")
                        .gsub(/>\s+</,"><")
                        .gsub(/>\s+\{\{/,">{{")
                        .gsub(/\}\}\s+</,"}}<")
                        .gsub(/\}\}\s+\{\{/,"}}{{")
                        .to_json
                    next "%s:Handlebars.compile(%s)" % [tname, content]
                }.join(",")

                common = Dir.glob(@dirs[:common_less] + "/**/*.less").map{|file|
                    IO.read(file)
                }.join("\n").strip + "\n"
                cls = name.gsub(".", "_");
                css = (Dir.glob(dir + "/*.css") + Dir.glob(dir + "/*.less")).map{|css|
                    content = common
                    content += ".%s { %s }" % [cls, IO.read(css)]
                    begin
                        next Less::Parser.new({
                            :paths => [css, @dirs[:style]],
                        }).parse(content).to_css({:compress => true})
                    rescue Exception => e
                        temp = File.join(@dirs[:output], "__temp.less")
                        File.open(temp, 'w') do |f|
                            f.puts content
                        end
                        raise [
                            "Less Exception processing #{css} - content saved to #{temp}",
                            e.message,
                            e.backtrace,
                        ].flatten.join("\n")
                    end
                }.join.to_json

                code = WRAPPER.gsub(/\$\$[A-Z]*?\$\$/, {
                    "$$BODY$$"      => source,
                    "$$CLASS$$"     => cls,
                    "$$CSS$$"       => css,
                    "$$NAME$$"      => name,
                    "$$STATIC$$"    => static,
                    "$$TEMPLATES$$" => templates,
                })

                next code
            }

            return result.join("\n")
        end

        # }}}

        private
        # {{{ template
        def template(str, hsh)
            return str.gsub(/\$\$[A-Z]*?\$\$/, hsh)
        end

        # }}}
    end
end

