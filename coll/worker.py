import argparse
from util.collectives import Collectives, Test
from util.network import get_ip, set_drop_prob, recv, send
import socket, struct

COLL_PORT = 55555
BROADCAST_IP = "10.0.0.255"

class MyCollectives(Collectives):
    def __init__(self, rank, world):
        self.rank = rank
        self.world = world
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("", COLL_PORT))
        self.sock.settimeout(50)
        print(f"MyCollectives Initialized")

    def AllReduce(self, input: list[int], output: list[int], op : str = "sum"):
        assert len(input), "input cannot be empty"
        assert len(input) == len(output), "input and output must have the same size"
        for index, value in enumerate(input):
            print(f"Looping over index {index} and value {value}")
            # This one is for reference. the p4 switch accepts the collect_t header in this format. We should construct a packet in the same manner
            # header collect_t {
            #     bit<32> index;
            #     int<32> value;
            #     }
            pkt = struct.pack(">Ii", index, value) #here >Ii creates 32+32 bits of index and value making it equal to the header in p4 switch
            #now we use the send method as suggested in the lab requirement to send the packet
            send(self.sock, pkt, (BROADCAST_IP, COLL_PORT))

        completed_indices = set()
        target_count = len(input)
        while len(completed_indices) < target_count:
            data_byte, add = recv(self.sock, 1024)
            
            #unpack the received data byte now
            idx, result = struct.unpack(">Ii", data_byte[:8]) #the response is the same 32 bit index + 32 bit value (updated after reduce) = 8 bytes, Ii is used again to unpack the same way as packed
            
            if 0 <= idx < target_count:
                output[idx] = result #store the result in worker's output array vector
                completed_indices.add(idx)
                print(f"[rank {self.rank}] chunk {idx} done -> {result}", flush=True)
                # break

        # TODO: Implement me. Ignore the op argument unless you are attempting the bonus

    def ReduceScatter(self, input: list[int], output: list[int]):
        assert len(input), "input cannot be empty"
        assert len(input) == (len(output) * self.world), "input size must be N * output size"
        # TODO: Implement me only if you attempt the bonus

    def AllGather(self, input: list[int], output: list[int]):
        assert len(input), "input cannot be empty"
        assert len(output) == (len(input) * self.world), "input size must be N * input size"
        # TODO: Implement me only if you attempt the bonus


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("rank", type=int)
    p.add_argument("world", type=int)
    args = p.parse_args()

    #replacing Collectives with MyCollectives because Collectives doesn't have init and it exists only after we've extended and initialized it here 
    coll = MyCollectives(args.rank, args.world)

    # TODO: Run more tests, do not rely only on the following

    data, expected = Test.data.ar_iota_rot(args.rank, args.world, 66)

    coll.AllReduce(data, data)

    print(f"expected({len(expected)}): {expected}")
    print(f"  actual({len(data)}): {data}")
