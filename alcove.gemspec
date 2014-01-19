# -*- encoding: utf-8 -*-

$:.push File.expand_path("../lib", __FILE__)
require "alcove/version"

Gem::Specification.new do |s|
    s.name              = "alcove"
    s.version           = Alcove::VERSION
    s.authors           = ["Kevin Pfab", "Mike Taczak"]
    s.email             = ["kevin.pfab@gmail.com"]
    s.homepage          = ""
    s.summary           = "A complete framework for building single page web-apps with object oriented UI components",
    s.description       = "An object oriented approach to UI components.  Widgets are discrete components combining html, css, and js into a simple object.  Everything is then packaged into a single JS file that is both minified and compressed."
    s.rubyforge_project = "alcove"
    s.files             = `git ls-files`.split("\n")
    s.test_files        = `git ls-files -- {test,spec,features}/*`.split("\n")
    s.executables       = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
    s.require_paths     = ["lib"]

    # specify any dependencies here; for example:
    s.add_runtime_dependency "juicer"
    s.add_runtime_dependency "less"
    s.add_runtime_dependency "libv8"
    s.add_runtime_dependency "therubyracer"
end

