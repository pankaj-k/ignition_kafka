def handleScheduleEvent():
	alarm_config = {
    "name": "QualityBad",
    "mode": "Bad Quality",
    "priority": "High",
    "activePipeline": "FactorySimulator_OPC_UA/factory-quality-pipeline"
}

def collect_atomic_tags(path, results):
    for tag in system.tag.browse(path).getResults():
        tag_type = str(tag["tagType"])
        full_path = str(tag["fullPath"])
        if tag_type == "AtomicTag":
            results.append(full_path)
        elif tag_type in ("Folder", "UdtInstance"):
            collect_atomic_tags(full_path, results)

all_tags = []
collect_atomic_tags("[default]Factory", all_tags)

for full_path in all_tags:
    check = system.tag.getConfiguration(full_path, False)
    if check and not check[0].get("alarms"):
        idx = full_path.rfind("/")
        parent = full_path[:idx]
        name   = full_path[idx+1:]
        system.tag.configure(parent, [{"name": name, "alarms": [alarm_config]}], "m")
        system.util.getLogger("AlarmProvisioner").info("Added QualityBad alarm to " + full_path)