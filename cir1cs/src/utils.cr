require "big.cr"

def write_to_file(x, target_file)
  File.write(target_file, x)
end

## logging

class SimpleLog

  getter :sLog, :sWarn, :time_start

  @@header  = "##### "
  @@section = "===== "
  
  def initialize(h : Hash(Symbol, String))

	@sLog, @sWarn, @caller, @flogs, @fwarn, @verbose = "", "", "", "", "", 1
	@time_start = Time.now
	
	@caller = h[:caller] if h.has_key?(:caller)
	@flogs = h[:flogs]
	@fwarn = h[:fwarn]
	@verbose = h[:verbose].to_i if [0, 1, 2].includes?(h[:verbose].to_i)

	@sLog = "\n"
	@sLog = @sLog + "................................................................................\n\n"	
	@sLog = @sLog + "SimpleLog\n\n"
	@sLog = @sLog + "called from #{@caller}\n\n" unless @caller == ""
	@sLog = @sLog + "#{@time_start}\n\n"
	@sLog = @sLog + "................................................................................\n\n"
  end  
  
  def verbose0
    @verbose = 0
  end
  
  def verbose1
    @verbose = 1
  end

  def verbose2
    @verbose = 2
  end
  
  # outputting to filesystem
  # TODO: option to open filehandle and write-as-you-go
  
  def dump
    File.write(@flogs, @sLog)
	File.write(@fwarn, @sWarn)
  end
  
  # aborting
  
  def abort(x)
    warn x
    dump
	  abort "aborting", 1
  end
  
  # adding to log
  
  
  def p(x="")
    @sLog = @sLog + "#{x}\n"
    puts "#{x}\n" if @verbose == 2
  end

  def header(x)
    @sLog = @sLog + "\n#{@@header}#{@@header}\n#{@@header}\n#{@@header}#{x}\n#{@@header}\n#{@@header}#{@@header}\n\n"
    puts "#{x}\n" if @verbose == 2
  end
  
  def section(x)
	@sLog = @sLog + "\n#{@@section}\n#{@@section}#{x}\n#{@@section}\n\n"
    puts "#{x}\n" if @verbose == 2
  end

  def warn(x="")
    s = x.to_s + "\n"
    @sLog = @sLog + "!WARN: " + s
    @sWarn = @sWarn + s
    puts s if @verbose > 0
  end
  
end


##################### maths
class Maths

  #modular exponentiation: a^exp [mod]
  def exp_modulo(a : BigInt, exp : BigInt, mod : BigInt)
    res = BigInt.new(1);
    while (exp > 0)
      if ((exp & 1) > 0)
        res = (res*a).modulo(mod);
      end
      exp >>= 1;
      a = (a*a).modulo(mod)
    end
    return res;
  end

end