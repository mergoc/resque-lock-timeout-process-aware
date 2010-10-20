require 'rake/testtask'
require 'rake/rdoctask'
require 'yard'
require 'yard/rake/yardoc_task'

task :default => :test

desc 'Run tests.'
Rake::TestTask.new(:test) do |task|
  task.test_files = FileList['test/*_test.rb']
  task.verbose = true
end

desc 'Build Yardoc documentation.'
YARD::Rake::YardocTask.new :yardoc do |t|
    t.files   = ['lib/**/*.rb']
    t.options = ['--output-dir', "doc/",
                 '--files', 'LICENSE',
                 '--readme', 'README.md',
                 '--title', 'resque-lock-timeout documentation']
end
begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "resque-lock-timeout-process-aware"
    gemspec.summary = "Fork of resque-lock-timeout that checks a saved process id to make sure the process is still running"
    gemspec.description = ""
    gemspec.email = "manuel@inakanetworks.com"
    gemspec.homepage = "http://github.com/mergoc/resque-lock-timeout-process-aware"
    gemspec.authors = ["Manuel Gomez"]
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end

require 'spec/rake/spectask'
Spec::Rake::SpecTask.new(:spec) do |spec|
  spec.libs << 'lib' << 'spec'
  spec.spec_files = FileList['spec/**/*_spec.rb']
end
