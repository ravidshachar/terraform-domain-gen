import sys
import ruamel.yaml

yaml = ruamel.yaml.YAML()
yaml.indent(mapping=2, sequence=2, offset=2)

with open(sys.argv[1], "r+") as inventory_file:
    doc = yaml.load(inventory_file)
    doc["include_vm_resource_groups"] = [prefix + "-rg" for prefix in list(sys.argv[2].split(","))]
    inventory_file.seek(0)
    yaml.dump(doc, inventory_file)
    inventory_file.truncate()