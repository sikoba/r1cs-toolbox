require "./utils.cr"

module Cir1cs

  VERSION = "0.1.0"

  # initialise logger

  @@sl = SimpleLog.new({
    :caller => "#{__FILE__}",
    :flogs => "./cir1cs.log",
    :fwarn => "./cir1cs.warn.log",
    :verbose => "1"
  })

  # inputs

  acpath = ARGV[0]
  @@sl.header "Reading file #{acpath}"
  @@sl.abort "file #{acpath} not found" if !File.file? acpath
  
  # initialise circuit variables

  inputs = Array(Int32).new
  nizkinputs = Array(Int32).new
  ops = Array( Array(Int32 | Array(Int32) | Symbol) ).new
  output = 0
  
  @@wires = Array(Int32).new
  
  # wires tracking

  def self.add_input_wires(inputs : Array(Int32))
    inputs.each do |iw|
	  @@sl.abort "input wire #{iw} already present" if @@wires.includes?(iw)
	  @@wires << iw
	end
  end
  
  def self.add_wires(inputs : Array(Int32), outputs : Array(Int32))
    inputs.each do |iw|
	  @@sl.abort "input wire #{iw} not found" unless @@wires.includes?(iw)
	end
    outputs.sort.each do |ow|
	  @@sl.abort "output wire #{ow} already present" if @@wires.includes?(ow)
	  @@sl.abort "a new wire number (#{ow}) should be exactly one more than the previous highest wire number (#{@@wires[-1]})" if @@wires[-1] + 1 != ow
	  @@wires << ow
	end
  end
  
  #############################################################################
  #
  # parse input file
  #
  
  # this input file has the structure
  #
  # total (1 line)
  # input
  # nizkinput
  # operations (currently: add mul const-mul-xx const-mul-neg-xx zerop split)
  # output (1 line)
  
  
  stage = 0
  line_count = 0 # count of line_count in input file
  circuit_line_count = 0 # declared line count in first line
  
  
  File.each_line acpath do |line|
    
    line_count += 1
    @@sl.p "\n** processing line #{line_count} [#{line}]\n"
	line = line.gsub(/\s*#.*$/, "")
    
    ### total
    
    if line =~ /^total (\d+)$/
      
      @@sl.abort "expecting total on first line" if stage > 0
      stage = 1
      
      circuit_line_count = $1.to_i

      @@sl.p "   total circuit line_count expected: #{circuit_line_count}"
    
    ### input

    elsif line =~ /^input (\d+)$/

      @@sl.abort "Unexpected input on this line" if stage != 1
      
      inputs << $1.to_i

      add_input_wires([$1.to_i])
	  
	  @@sl.p "   added input wire #{$1.to_i}"

    ### nizkinputs
    
    elsif line =~ /^nizkinput (\d+)$/
      
      @@sl.abort "Unexpected nizkinput on this line" if stage != 1
      
      nizkinputs << $1.to_i

      add_input_wires([$1.to_i])
	  
	  @@sl.p "   added nizkinput wire #{$1.to_i}"

    ### output
      
    elsif line =~ /^output (\d+)$/

      @@sl.abort "Unexpected output on this line" if stage != 2
      stage = 3
      
      output = $1.to_i
	  
	  add_wires([] of Int32, [$1.to_i])
	  
	  @@sl.p "   added output wire #{$1.to_i}"
    
    else    

    ### gates
    
      @@sl.abort "Unexpected gate on this line" unless [1, 2].includes?(stage)
      stage = 2    

      # add

      if line =~ /^add in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
  
        a = Array(Int32).new
        a = $2.split.map{ |x| x.to_i }
        abort "Inconsistent number of inputs:  #{line} " if a.size != $1.to_i
        ops << [ :add, a, $3.to_i ]
		
        add_wires(a, [$3.to_i])

		@@sl.p "   add #{a} = #{$3.to_i}"

      # mul
      
      elsif line =~ /^mul in (\d+) <([\s\d]+)> out 1 <(\d+)>$/
      
        a = Array(Int32).new
        a = $2.split.map{ |x| x.to_i }
        abort "Inconsistent number of inputs:  #{line} " if a.size != $1.to_i      
        ops << [ :mul, a, $3.to_i ]
		
		add_wires(a, [$3.to_i])

		@@sl.p "   mul #{a} = #{$3.to_i}"
      
      # const-mul-neg-xx
      
      elsif line =~ /^const-mul-neg-(\d+) in 1 <(\d+)> out 1 <(\d+)>$/

        ops << [ :const_mul_neg, $1.to_i, $2.to_i, $3.to_i ]
		
		@@sl.p "   const_mul_neg -#{$1.to_i}_C x #{$2.to_i} = #{$3.to_i}"
		
		add_wires([$2.to_i], [$3.to_i])
      
      # const-mul-xx
      
      elsif line =~ /^const-mul-(\d+) in 1 <(\d+)> out 1 <(\d+)>$/

        ops << [ :const_mul, $1.to_i, $2.to_i, $3.to_i ]
		
		@@sl.p "   const_mul #{$1.to_i}_C x #{$2.to_i} = #{$3.to_i}"
	  
	    add_wires([$2.to_i], [$3.to_i])

      # split
      
      elsif line =~ /^split in 1 <(\d+)> out (\d+) <([\s\d]+)>$/

        a = Array(Int32).new
        a = $3.split.map{ |x| x.to_i }
        abort "Inconsistent number of wires:  #{line} " if a.size != $2.to_i
        ops << [ :split, $1.to_i, a ]
		
		@@sl.p "   split #{$1.to_i} => #{a}"
		
		add_wires([$1.to_i], a)

      # zerop
      
      elsif line =~ /^zerop in 1 <(\d+)> out (\d+) <([\s\d]+)>$/

        a = Array(Int32).new
        a = $3.split.map{ |x| x.to_i }
        abort "Inconsistent number of outputs:  #{line} " if a.size != $2.to_i
        ops << [ :zerop, $1.to_i, a ]
		
		@@sl.p "   zerop #{$1.to_i} => #{a}"

        add_wires([$1.to_i], a)

      # unknown gate #
	
	  else

        ops << [ :imlost ]
		
        @@sl.p "unknown operation"
    
      end
	
	end
      
  end
  
  @@sl.abort "Line number panic. Expected #{circuit_line_count}, found #{line_count - 1} " if circuit_line_count != line_count - 1
  
  # get one-input
  
  oneinput = inputs.pop

  # print report of artitmetic circuit import
  
  @@sl.section "Result of arithemtic circuit import"

  @@sl.p "inputs"
  @@sl.p inputs.inspect
  
  @@sl.p "\noneinput"
  @@sl.p oneinput.inspect

  @@sl.p "\nnizkinputs"
  @@sl.p nizkinputs.inspect
  
  @@sl.p "\nops"
  ops.each do |a|
    @@sl.p a.inspect
  end

  @@sl.p "\noutput"
  @@sl.p output.inspect

  @@sl.p "\nwires"
  @@sl.p @@wires.inspect
  
  @@sl.dump
  
  
end