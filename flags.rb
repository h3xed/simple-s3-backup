# Set flags
flags = Hash[ARGV.join(' ').scan(/--?([^=\s]+)(?:=(\S+))?/)]

# Build flags accessors

%w(only_db only_files).each do |flag|
  define_method("#{flag}?") { flags.keys.include?(flag) }
end