from util import controller


class CollController(controller.Client):
    def setup(self):
        super().setup()
        hosts = self.topo.get_hosts_connected_to(self.sw)
        n = len(hosts) #n value calculated
        #populate the register values
        self.register_write("ingress.num_workers_reg", 0, n)
        self.register_write("ingress.count_reg", 0, 0)
        self.register_write("ingress.pool_reg", 0, 0)
        print(f"[{self.sw}] - n value (world size) set to {n}")

    def reset(self):
        super().reset()
        # self.register_reset("ingress.num_workers_reg")
        self.register_reset("ingress.count_reg")
        self.register_reset("ingress.pool_reg")
        self.register_reset("ingress.slot_index_reg")


if __name__ == "__main__":
    c = controller.App(CollController())
