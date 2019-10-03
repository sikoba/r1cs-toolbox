require "big.cr"
require "./gate.cr"


module Cir1cs

##################### J1CS: a helper class for basic functionalities of the file format
class J1CS 

def initialize(@gate_keeper : GateKeeper)
end


def inputs_to_json(inputs : Array(String), witnessess : Array(String))
  str_res = JSON.build do |json|
      json.object do 
          json.field "inputs", to_json(inputs)
          json.field "witnesses", to_json(witnessess)
      end
  end
  return str_res;
end



def json_header(constraint_nb : Int32, prime : BigInt, instance_nb : UInt32, witness_nb : Int32)
    return "{\"r1cs\":{\"constraint_nb\":#{constraint_nb},\"extension_degree\":1,\"field_characteristic\":#{prime},\"instance_nb\":#{instance_nb},\"version\":\"1.0\",\"witness_nb\":#{witness_nb}}}"
end

def to_json_str(a : Array(Tuple(UInt32,BigInt)), b : Array(Tuple(UInt32,BigInt)), c : Array(Tuple(UInt32,BigInt)))
  str_res = JSON.build do |json|
      json.object do 
          json.field "A", to_json(a);
          json.field "B", to_json(b);
          json.field "C", to_json(c);
      end
  end
  return str_res;
end

def to_json(lc : Array(Tuple(UInt32,String)))
  str = JSON.build do |json|
       json.array do
           lc.each do |item|
               json.array do
                   json.number @gate_keeper.getWireIdx(item[0])
                   json.string item[1]
               end
           end
       end
   end
   return JSON.parse(str)      #TODO it must be possible to generate the json directly
end

def to_json(a : Array(String))
  str = JSON.build do |json|
       json.array do
           a.each do |item|
              json.string item
           end
       end
   end
   return JSON.parse(str)      #TODO it must be possible to generate the json directly
end

def to_json(lc : Array(Tuple(UInt32,BigInt)))
  str = JSON.build do |json|
      json.array do
          lc.each do |item|
              json.array do
                  json.number @gate_keeper.getWireIdx(item[0])
                  json.string item[1].to_s
              end
          end
      end
  end
  return JSON.parse(str)      #TODO it must be possible to generate the json directly
end

def to_json(lc : LinearCombination)
  return to_json(lc.@lc);
end



end   ##class J1CS


end   ## module