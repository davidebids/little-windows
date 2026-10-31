#!/usr/bin/env python3
"""Check the compiled App Intents metadata, not just source phrase strings.

Usage: python3 Scripts/validate_voice_timer_shortcuts.py \
    /path/to/LittleWindows.app/Metadata.appintents/extract.actionsdata
"""

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


def validate(path):
    data = json.loads(path.read_text())
    enums = {item["identifier"]: item for item in data["enums"]}
    shortcuts = data["autoShortcuts"]
    assert len(shortcuts) <= 10, "Exceeded the promoted-shortcut limit"
    # A standalone "Little" amount collided with the first app-name token
    # during flexible extraction. Keep that wording as an alias, not a title.
    amounts = {case["identifier"]: case["displayRepresentation"] for case in enums["DiaperAmount"]["cases"]}
    app_name_words = {"little", "windows"}
    assert all(rep["title"]["key"].casefold() not in app_name_words for rep in amounts.values()), "An amount title collides with the app name"
    assert amounts["little"]["title"]["key"] == "Small"
    assert "Little" in {x["key"] for x in amounts["little"].get("synonyms", [])}, "Little must remain a supported spoken amount"
    cases = enums["VoiceTimerKind"]["cases"]
    kind_ids = {case["identifier"] for case in cases}
    expected = {
        "sleep", "nap", "nightSleep", "nightWaking", "nursing", "nursingLeft", "nursingRight",
        "pumping", "bottle", "solidMeal", "otherFeed", "tummyTime", "storyTime", "brushTeeth",
        "indoorPlay", "outdoorPlay", "screenTime", "bath", "customActivity", "customTimer",
        "exercise", "physicalTherapy", "socialActivity",
    }
    assert expected == kind_ids, f"Timer catalog changed: {expected ^ kind_ids}"

    owners = defaultdict(set)
    bindings = set()
    expanded_phrase_count = 0
    for shortcut in shortcuts:
        action_id = shortcut["actionIdentifier"]
        parameters = {p["name"]: p for p in data["actions"][action_id]["parameters"]}
        for phrase in shortcut["phraseTemplates"]:
            template = phrase["key"].replace("${applicationName}", "Little Windows")
            names = re.findall(r"\$\{([^}]+)\}", template)
            assert len(names) <= 1, f"Phrase has multiple parameters: {template}"
            if not names:
                owners[template.casefold()].add(action_id)
                expanded_phrase_count += 1
                continue
            parameter_name = names[0]
            parameter = parameters[parameter_name]
            enum_id = parameter["valueType"]["linkEnumeration"]["wrapper"]["identifier"]
            for case in enums[enum_id]["cases"]:
                representation = case["displayRepresentation"]
                words = [representation["title"]["key"]]
                words.extend(synonym["key"] for synonym in representation.get("synonyms", []))
                for word in words:
                    expanded = template.replace("${" + parameter_name + "}", word).casefold()
                    owners[expanded].add(action_id)
                    expanded_phrase_count += 1
                bindings.add((action_id, parameter_name, case["identifier"]))

    assert expanded_phrase_count <= 1_000, f"Expanded phrase budget exceeded: {expanded_phrase_count}"

    collisions = {phrase: actions for phrase, actions in owners.items() if len(actions) > 1}
    assert not collisions, f"Competing phrase owners: {collisions}"
    start = "StartCareTimerByVoiceIntent"
    manage = "ManageCareTimerByVoiceIntent"
    for kind_id in kind_ids:
        assert (start, "timerKind", kind_id) in bindings, f"No start binding for {kind_id}"
        for selector in ["pauseTimer", "resumeTimer", "finishTimer", "resetTimer", "discardTimer", "correctTimer"]:
            assert (manage, selector, kind_id) in bindings, f"No {selector} binding for {kind_id}"

    log = "LogCareByVoiceIntent"
    diaper = "LogDiaperByVoiceIntent"
    assert "LogSleepByVoiceIntent" not in {x["actionIdentifier"] for x in shortcuts}, "Sleep must not compete with the broad logging route"
    assert "LogSleepByVoiceIntent" in data["actions"], "Preserve the completed-sleep action for saved Shortcuts"
    care_ids = {case["identifier"] for case in enums["VoiceCareKind"]["cases"]}
    expected_care = {
        "bottle", "diaper", "sleep", "nursing", "pumping", "temperature", "bloodPressure",
        "heartRate", "oxygenSaturation", "respiratoryRate", "glucose", "weight", "pain", "symptom", "activity", "note",
        "wetDiaper", "dirtyDiaper", "mixedDiaper", "potty", "pottyPee", "pottyPoop", "pottyBoth",
        "solidMeal", "otherFeed", "height", "headCircumference", "tummyTime", "storyTime", "brushTeeth",
        "indoorPlay", "outdoorPlay", "screenTime", "bath", "exercise", "physicalTherapy", "socialActivity",
        "littlePee", "mediumPee", "bigPee", "littlePoo", "mediumPoo", "bigPoo",
        "littleMixedDiaper", "mediumMixedDiaper", "bigMixedDiaper",
    }
    assert care_ids == expected_care, f"Care log catalog changed: {care_ids ^ expected_care}"
    diaper_ids = {case["identifier"] for case in enums["VoiceDiaperEntry"]["cases"]}
    general_ids = {case["identifier"] for case in enums["VoiceGeneralCareEntry"]["cases"]}
    assert general_ids == care_ids - diaper_ids - {"diaper"}, "General and diaper logging vocabularies must partition the care catalog"
    for care_id in care_ids:
        if care_id in general_ids:
            assert (log, "entry", care_id) in bindings, f"No general logging phrase for {care_id}"
        else:
            assert (diaper, "spokenEntry", care_id) in bindings, f"No dedicated diaper phrase for {care_id}"
        assert ("LastCareEntryByVoiceIntent", "kind", care_id) in bindings, f"No last-entry phrase for {care_id}"
    diaper_cases = {case["identifier"]: case for case in enums["VoiceDiaperEntry"]["cases"]}
    diaper_ids = {
        "wetDiaper", "dirtyDiaper", "mixedDiaper", "littlePee", "mediumPee", "bigPee",
        "littlePoo", "mediumPoo", "bigPoo", "littleMixedDiaper", "mediumMixedDiaper", "bigMixedDiaper",
    }
    assert set(diaper_cases) == diaper_ids, "Incomplete diaper follow-up choices"
    care_cases = {case["identifier"]: case for case in enums["VoiceCareKind"]["cases"]}
    for diaper_id in diaper_ids:
        assert diaper_cases[diaper_id]["displayRepresentation"] == care_cases[diaper_id]["displayRepresentation"], f"Diaper follow-up wording differs: {diaper_id}"
    log_parameters = {parameter["name"] for parameter in data["actions"][log]["parameters"]}
    assert {
        "diaperEntry", "diaperKind", "peeAmount", "pooAmount", "pooColor", "pooTexture", "diaperRash",
        "pottyKind", "pottyLocation", "pottyAccident", "date", "notes",
    } <= log_parameters, "Compiled care action is missing metadata fields"

    diaper_parameters = {parameter["name"] for parameter in data["actions"][diaper]["parameters"]}
    assert {"spokenEntry", "diaperEntry", "profile", "diaperKind", "peeAmount", "pooAmount", "pooColor", "pooTexture", "diaperRash", "date", "notes"} <= diaper_parameters
    for case in enums["VoiceDiaperPhrase"]["cases"]:
        assert (diaper, "spokenEntry", case["identifier"]) in bindings, "Unregistered diaper phrase form"
    diaper_words = {"diaper"}
    for case in diaper_cases.values():
        rep = case["displayRepresentation"]
        diaper_words.add(rep["title"]["key"].casefold())
        diaper_words.update(x["key"].casefold() for x in rep.get("synonyms", []))

    critical = {
        "log sleep": log,
        "record sleep": log,
        "log diaper": diaper,
        "log a diaper": diaper,
        "record a diaper": diaper,
        "start sleep": start,
        "start nursing left": "StartNursingLeftByVoiceIntent",
        "start nursing right": "StartNursingRightByVoiceIntent",
        "switch nursing sides": "SwitchActiveNursingSideByVoiceIntent",
        "start pumping": start,
        "finish pumping": manage,
        "start bottle": start,
        "finish bottle": manage,
        "stop the timer": manage,
        "pause timer": manage,
        "resume timer": manage,
        "finish timer": manage,
        "save timer": manage,
        "reset timer": manage,
        "discard timer": manage,
        "show active timers": "ActiveCareTimersByVoiceIntent",
    }
    for activity in ["tummy time", "story time", "reading", "tooth brushing", "indoor play", "outdoor play", "screen time", "bath", "custom activity", "custom timer"]:
        critical[f"start {activity}"] = start
        for verb in ["pause", "stop", "resume", "finish", "save", "finish and save", "stop and save", "reset", "discard"]:
            critical[f"{verb} {activity}"] = manage
        critical[f"correct {activity} start time"] = manage
    for entry in [
        "pee", "poo", "poop", "wet diaper", "dirty diaper", "mixed diaper", "pee diaper", "poo diaper", "poopy diaper",
        "pee and poo", "pee and poop", "pee and poo diaper", "pee and poop diaper", "wet and dirty diaper",
        "potty", "potty pee", "potty poo", "potty poop", "potty pee and poo", "potty pee and poop",
        "solid meal", "solids", "other feed", "height", "length", "head circumference",
        "tummy time", "story time", "reading", "tooth brushing", "brushing teeth", "indoor play", "outdoor play",
        "screen time", "bath", "exercise", "physical therapy", "social activity",
    ]:
        critical[f"log {entry}"] = log
        critical[f"record {entry}"] = log
        critical[f"get last {entry}"] = "LastCareEntryByVoiceIntent"
    for entry in ["little p", "small p", "medium p", "big p", "large p"]:
        critical[f"log {entry}"] = log
        critical[f"record {entry}"] = log
        critical[f"get last {entry}"] = "LastCareEntryByVoiceIntent"
    for entry in ["wet diaper", "dirty diaper", "mixed diaper", "pee diaper", "poo diaper", "poop diaper", "poopy diaper"]:
        critical[f"log a {entry}"] = log
    for amount in ["little", "small", "medium", "big", "large"]:
        for noun in ["pee", "poo", "poop", "wet diaper", "dirty diaper", "mixed diaper"]:
            critical[f"log {amount} {noun}"] = log
            critical[f"record {amount} {noun}"] = log
            if noun.endswith("diaper"):
                critical[f"log a {amount} {noun}"] = log
    for prefix, expected_action in critical.items():
        phrase = f"{prefix} in little windows"
        if expected_action == log and re.sub(r"^(log|record)( a)? ", "", prefix) in diaper_words:
            expected_action = diaper
        assert owners.get(phrase) == {expected_action}, f"Incorrect phrase registration: {phrase}: {owners.get(phrase)}"
    print(f"PASS: {len(kind_ids)} timer kinds, seven lifecycle bindings each, {len(care_ids)} care log kinds, {len(critical)} critical phrases, {len(shortcuts)} promoted shortcuts, {expanded_phrase_count}/1000 expanded phrases; no competing phrase owners.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metadata", type=Path)
    args = parser.parse_args()
    validate(args.metadata)
