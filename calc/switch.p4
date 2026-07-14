#include <core.p4>
#include <v1model.p4>

const bit<16> ETH_TYPE_CALC = 0x7777;
// This solution extends the L2 switch's DMAC implementation for non-calculator packets
header ethernet_t {
  bit<48> dstAddr;
  bit<48> srcAddr;
  bit<16> etherType;
}

header calc_t {
  bit<8> op;
  int<32> a;
  int<32> b;
}

struct headers_t {
  ethernet_t eth;
  calc_t calcu;
}

struct metadata_t { }

parser parse(packet_in pkt, out headers_t hdr,
             inout metadata_t meta, inout standard_metadata_t std) {
  // TODO: Implement me
  state start {
    pkt.extract(hdr.eth);
    transition select(hdr.eth.etherType) {
      ETH_TYPE_CALC: calc_parser;
      default: accept;
    }
  }
  state calc_parser {
    pkt.extract(hdr.calcu);
    transition accept;
  }
}

// === IMPORTANT NOTE ===
//
// There is currently a bug with the BMv2 switch P4 compiler
// When reading a signed register, and then using the result for a signed operation,
// the switch actually performs that operation as unsigned instead. This is usually
// fine (e.g. add/sub works fine), but comparissons can fail. This can cause your
// your min/max/shl/shr operations to fail. To avoid it please use the SIGNED macro
// For example:
//
//      int<32> val = -42;
//      signed_register.read(val, 0)
//      if (val < 42) ...         // This will return false
//      if (SIGNED(32,val) < 42) ... // This will return true
//
#define SIGNED(bits,var) ((int<bits>)(bit<bits>)var)

register<int<32>>(1) mem;
control calculator(inout headers_t hdr, inout metadata_t meta,
                   inout standard_metadata_t std) {

  // TODO: Implement the remaining calculator block
  //
  // - Implement the operations according to their specification
  // - Apply the one requested in the calc header (use a table)
  // - Decide how to handle sending the result back. Should that
  //   be handled here, or fall through to standard forwarding?
  
  // Implementing individual actions. a pivot from the poc version of sequential if conditions
  int<32> existing_mem;
  int<32> new_mem;
  action add() {
    hdr.calcu.a = hdr.calcu.a + hdr.calcu.b;
  }
  action min() {
    if (SIGNED(32,hdr.calcu.a) < SIGNED(32,hdr.calcu.b)) {
      hdr.calcu.a = hdr.calcu.a;
      } else {
        hdr.calcu.a = hdr.calcu.b;
      }
  }
  action max() {
    if (SIGNED(32,hdr.calcu.a) > SIGNED(32,hdr.calcu.b)) {
      hdr.calcu.a = hdr.calcu.a;
      } else {
        hdr.calcu.a = hdr.calcu.b;
      }
  }
  action neg() { hdr.calcu.a = -hdr.calcu.a; }
  action shl() { hdr.calcu.a = hdr.calcu.a << 1; }
  action shr() { hdr.calcu.a = hdr.calcu.a >> 1; }
  action mstore() {
    mem.read(existing_mem, 0);
    mem.write(0, hdr.calcu.a);
    hdr.calcu.a = existing_mem;
  }
  action mload () {
    mem.read(existing_mem,0);
    hdr.calcu.a = existing_mem;
  }
  action madd () {
    mem.read(existing_mem,0);
    new_mem = SIGNED(32, existing_mem) + hdr.calcu.a;
    mem.write(0, new_mem);
    hdr.calcu.a = existing_mem;
  }
  action mmin () {
    mem.read(existing_mem,0);
    if (SIGNED(32,existing_mem) < SIGNED(32,hdr.calcu.a)) {
      new_mem = existing_mem;
    } else {
      new_mem = hdr.calcu.a;
    }
    mem.write(0, new_mem);
    hdr.calcu.a = existing_mem;
  }
  action mmax () {
    mem.read(existing_mem,0);
    if (SIGNED(32,existing_mem) < SIGNED(32,hdr.calcu.a)) {
      new_mem = hdr.calcu.a;
    } else {
      new_mem = existing_mem;
    }
    mem.write(0, new_mem);
    hdr.calcu.a = existing_mem;
  }
  action mneg () {
    mem.read(existing_mem,0);
    new_mem = -SIGNED(32, existing_mem);
    mem.write(0, new_mem);
    hdr.calcu.a = existing_mem;
  }
  action mshl () {
    mem.read(existing_mem,0);
    new_mem = SIGNED(32,existing_mem) << 1;
    mem.write(0,new_mem);
    hdr.calcu.a = existing_mem;
  }
  action mshr() {
      mem.read(existing_mem,0);
      new_mem = SIGNED(32,existing_mem) >> 1;
      mem.write(0,new_mem);
      hdr.calcu.a = existing_mem;
  }

  //table implemented as suggested in the vanilla comments
  table calculate {
    key = { hdr.calcu.op: exact; }
    actions = { add; min; max; neg; shl; shr; mstore; mload; madd; mmin; mmax; mneg; mshl; mshr; NoAction; }
    size = 48;
    default_action = NoAction();
    const entries = {
      1: add();
      2: min();
      3: max();
      4: neg();
      5: shl();
      6: shr();
      11: mstore();
      12: mload();
      13: madd();
      14: mmin();
      15: mmax();
      16: mneg();
      17: mshl();
      18: mshr();
    }
  }

  apply {
    calculate.apply();
  }
}

control ingress(inout headers_t hdr, inout metadata_t meta,
                inout standard_metadata_t std) {
  register<bit<16>>(1) flood_mgid;

  action flood() { flood_mgid.read(std.mcast_grp, 0); }
  action forward(bit<9> port) { std.egress_spec = port; }

  table dmac {
    key            = { hdr.eth.dstAddr : exact; }
    actions        = { forward; flood; }
    size           = 4096;
    default_action = flood();
  }
  
  calculator() calc;

  // TODO: Implement the remaining ingress block
  //
  // - The calculator logic should only run on calc packets.
  //   Other packets should be forwarded normally
  // - For calculator packets think how to send a result back

  apply { 
    if (hdr.calcu.isValid()) {
      calc.apply(hdr, meta, std);

      //swap macs for reply to client
      bit<48> tmp_mac = hdr.eth.dstAddr;
      hdr.eth.dstAddr = hdr.eth.srcAddr;
      hdr.eth.srcAddr = tmp_mac;

      std.egress_spec = std.ingress_port;
    } else {
      dmac.apply();
    }
  }
}

control egress(inout headers_t hdr, inout metadata_t meta,
               inout standard_metadata_t std) {
  const bit<32> PKT_INSTANCE_TYPE_REPLICATION = 5;
  apply {
    if (std.instance_type == PKT_INSTANCE_TYPE_REPLICATION && std.egress_port == std.ingress_port) {
      mark_to_drop(std);
    }
  }
}

control deparse(packet_out pkt, in headers_t hdr) {
  // TODO: Implement me
  apply { 
    pkt.emit(hdr.eth);
    pkt.emit(hdr.calcu);
  }
}

control no_checksum(inout headers_t hdr, inout metadata_t meta) { apply {  } }

V1Switch(parse(),no_checksum(),ingress(),egress(),no_checksum(),deparse()) main;