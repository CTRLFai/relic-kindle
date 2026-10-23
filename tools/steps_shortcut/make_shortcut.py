#!/usr/bin/env python3
"""Generate the unsigned "Relic Steps" iOS Shortcut (XML plist).

The Health action format is copied from real shared Shortcuts (client 2038),
not guessed. Placeholders __TODOIST_TOKEN__ and __PROJECT_ID__ are filled in on
Mike's Mac by build.sh, which also signs the file. Never commit a filled copy.

What it does: Find Health Samples (Steps, Start Date in the last 2 days,
grouped by day) -> for each day "YYYY-MM-DD <rounded total>;" -> POST a Todoist
task "Relic steps" to the Relic project with those lines as the description.
"""
import plistlib, sys, uuid

def U(): return str(uuid.uuid4()).upper()

def out(uid, name): return {"OutputName": name, "OutputUUID": uid, "Type": "ActionOutput"}
def att(v): return {"Value": v, "WFSerializationType": "WFTextTokenAttachment"}
def tstr(s, attachments=None):
    return {"Value": {"attachmentsByRange": attachments or {}, "string": s}, "WFSerializationType": "WFTextTokenString"}
def dict_param(items):
    return {"Value": {"WFDictionaryFieldValueItems": [
        {"WFItemType": 0, "WFKey": tstr(k), "WFValue": v} for k, v in items]},
        "WFSerializationType": "WFDictionaryFieldValue"}
def act(ident, params): return {"WFWorkflowActionIdentifier": "is.workflow.actions." + ident, "WFWorkflowActionParameters": params}

OBJ = "￼"
health, loop, date_p, val_p, rnd, line, end_loop, body, post = (U() for _ in range(9))
repeat_item = {"Type": "Variable", "VariableName": "Repeat Item"}

actions = [
    act("filter.health.quantity", {
        "UUID": health,
        "WFContentItemFilter": {"Value": {
            "WFActionParameterFilterPrefix": 1,
            "WFActionParameterFilterTemplates": [
                {"Bounded": True, "Operator": 4, "Property": "Type", "Removable": False,
                 "Values": {"Enumeration": {"Value": "Steps", "WFSerializationType": "WFStringSubstitutableState"}}},
                # 1001 = "is in the last", Unit 16 = days (seen with a variable Number in a real Shortcut)
                {"Bounded": True, "Operator": 1001, "Property": "Start Date", "Removable": False,
                 "Values": {"Number": 2, "Unit": 16}},
            ],
            "WFContentPredicateBoundedDate": False},
            "WFSerializationType": "WFContentPredicateTableTemplate"},
        "WFContentItemLimitEnabled": False,
        "WFHKSampleFilteringGroupBy": "Day",
    }),
    act("repeat.each", {"GroupingIdentifier": loop, "WFControlFlowMode": 0, "WFInput": att(out(health, "Health Samples"))}),
    act("properties.health.quantity", {"UUID": date_p, "WFContentItemPropertyName": "Start Date", "WFInput": att(repeat_item)}),
    act("properties.health.quantity", {"UUID": val_p, "WFContentItemPropertyName": "Value", "WFInput": att(repeat_item)}),
    act("round", {"UUID": rnd, "WFInput": att(out(val_p, "Value")), "WFRoundTo": "Ones Place"}),
    act("gettext", {"UUID": line, "WFTextActionText": tstr(OBJ + " " + OBJ + ";", {
        "{0, 1}": {**out(date_p, "Start Date"), "Aggrandizements": [
            {"CoercionItemClass": "WFDateContentItem", "Type": "WFCoercionVariableAggrandizement"},
            {"Type": "WFDateFormatVariableAggrandizement", "WFDateFormatStyle": "ISO 8601",
             "WFISO8601IncludeTime": False}]},
        "{2, 1}": out(rnd, "Rounded Number"),
    })}),
    act("repeat.each", {"GroupingIdentifier": loop, "UUID": end_loop, "WFControlFlowMode": 2}),
    act("gettext", {"UUID": body, "WFTextActionText": tstr(OBJ, {"{0, 1}": out(end_loop, "Repeat Results")})}),
    act("downloadurl", {
        "UUID": post,
        "WFURL": "https://api.todoist.com/api/v1/tasks",
        "WFHTTPMethod": "POST",
        "ShowHeaders": True,
        "WFHTTPHeaders": dict_param([("Authorization", tstr("Bearer __TODOIST_TOKEN__"))]),
        "WFHTTPBodyType": "JSON",
        "WFJSONValues": dict_param([
            ("content", tstr("Relic steps")),
            ("project_id", tstr("__PROJECT_ID__")),
            ("description", tstr(OBJ, {"{0, 1}": out(body, "Text")})),
        ]),
    }),
]

shortcut = {
    "WFQuickActionSurfaces": [],
    "WFWorkflowActions": actions,
    "WFWorkflowClientVersion": "2038.0.2.4",
    "WFWorkflowHasOutputFallback": False,
    "WFWorkflowHasShortcutInputVariables": False,
    "WFWorkflowIcon": {"WFWorkflowIconGlyphNumber": 59812, "WFWorkflowIconStartColor": 4282601983},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowOutputContentItemClasses": [],
    "WFWorkflowTypes": [],
}

path = sys.argv[1] if len(sys.argv) > 1 else "relic-steps.unsigned.plist"
with open(path, "wb") as f:
    plistlib.dump(shortcut, f, fmt=plistlib.FMT_XML)
print("wrote", path)
