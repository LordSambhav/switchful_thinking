from util import controller


class MyController(controller.Client):
    def __init__(self):
        super().__init__("s1", topo="log/topology.json")
        print("Hello from MyController")


if __name__ == "__main__":
    c = controller.App(MyController())

