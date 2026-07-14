from scapy.all import Packet
from scapy.all import *

from util.calculator import Op, Calculator, CalculatorTester

class Calc(Packet):
  # TODO: Define the calculator header
  name = "Calc Protocol"
  fields_desc = [ByteEnumField("op", 0, Op), SignedIntField("a", 0), SignedIntField("b",0)]


dummyMac = "00:00:00:00:05:05"
class MyCalculator(Calculator):
    def exec(self, op : Op, a : int = 0, b : int = 0):
      # TODO: Implement me
      #
      # - Use Scapy to send a Calc packet to the switch to perform
      #   the requested operation
      # - Wait for the switch's response and return it
      #   See util/calculator.py how this function is used
      pkt = Ether(dst=dummyMac, type=0x7777) / Calc(op=int(op), a=a, b=b)
      # pkt.show()
      print(f"The Request is {pkt}")
      response = srp1(pkt, timeout=5, filter=f"ether src {dummyMac}", iface="eth0")
      print(f"The Response is {response}")
      if response and response.haslayer(Calc):
         return response[Calc].a
      
      return None

bind_layers(Ether, Calc, type=0x7777)

if __name__ == "__main__":
    c = MyCalculator()
    # Feel free to run operations directly during dev. E.g:
    #
    print( c.max(6,45) ) # should print 3
    #
    # In the end however, the following has to pass:
    CalculatorTester().test(c)
    
    
# run with: mx h1 python client.py
