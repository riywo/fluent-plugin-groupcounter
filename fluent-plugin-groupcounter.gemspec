# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "fluent-plugin-groupcounter"
  s.version     = "0.2.2"
  s.authors     = ["Ryosuke IWANAGA", "Naotoshi SEO"]
  s.email       = ["@riywo", "sonots@gmail.com"]
  s.homepage    = "https://github.com/riywo/fluent-plugin-groupcounter"
  s.summary     = %q{Fluentd plugin to count like SELECT COUNT(\*) GROUP BY}
  s.description = %q{Fluentd plugin to count like SELECT COUNT(\*) GROUP BY}

  s.rubyforge_project = "fluent-plugin-groupcounter"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "fluentd"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "pry"
  s.add_development_dependency "pry-nav"
end
