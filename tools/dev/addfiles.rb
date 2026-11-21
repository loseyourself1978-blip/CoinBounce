# ruby addfiles.rb <CoinBounce 下的组名> <文件名，不带路径…> [--tests]：把新文件加进 App target；--tests 时也编进测试 target（给测试直接用的内核文件）
# ruby addfiles.rb --test-file <文件…>：把测试文件加进 CoinBounceTests
require 'xcodeproj'
proj = Xcodeproj::Project.open(File.expand_path('../../ios/CoinBounce.xcodeproj', __dir__))
app = proj.targets.find { |t| t.name == 'CoinBounce' }
tests = proj.targets.find { |t| t.name == 'CoinBounceTests' }
args = ARGV.dup
if args.first == '--test-file'
  group = proj.main_group['CoinBounceTests']
  args[1..].each do |f|
    next if group.files.any? { |r| r.path == f }
    tests.add_file_references([group.new_file(f)]); puts "tests += #{f}"
  end
else
  also = args.delete('--tests')
  parent = proj.main_group['CoinBounce']
  group = parent[args[0]] || parent.new_group(args[0], args[0])
  args[1..].each do |f|
    ref = group.files.find { |r| r.path == f }
    unless ref
      ref = group.new_file(f); app.add_file_references([ref]); puts "app += #{f}"
    end
    if also && !tests.source_build_phase.files_references.include?(ref)
      tests.add_file_references([ref]); puts "tests += #{f}"
    end
  end
end
proj.save
