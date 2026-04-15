GLOBAL FUNCTION ResolveManifestGroup {
    PARAMETER groupDefinition.

    LOCAL resolvedParts TO LIST().
    LOCAL identifiers TO groupDefinition["identifiers"].
    LOCAL lookupType TO groupDefinition["lookup_type"].

    FOR identifier IN identifiers {
        LOCAL foundParts TO LIST().

        IF lookupType = "part_name" {
            SET foundParts TO SHIP:PARTSNAMED(identifier).
        } ELSE IF lookupType = "part_title" {
            SET foundParts TO SHIP:PARTSTITLED(identifier).
        } ELSE {
            RETURN resolvedParts.
        }.

        FOR foundPart IN foundParts {
            IF NOT resolvedParts:CONTAINS(foundPart) {
                resolvedParts:ADD(foundPart).
            }.
        }.
    }.

    RETURN resolvedParts.
}.

GLOBAL FUNCTION ValidateManifestGroup {
    PARAMETER groupDefinition, resolvedParts.

    IF groupDefinition:HASKEY("required_count") {
        RETURN resolvedParts:LENGTH >= groupDefinition["required_count"].
    }.

    RETURN NOT resolvedParts:EMPTY.
}.

GLOBAL FUNCTION ResolveManifest {
    PARAMETER manifest.

    LOCAL resolvedManifest TO LEXICON().

    FOR groupName IN manifest:KEYS {
        LOCAL groupDefinition TO manifest[groupName].
        LOCAL resolvedParts TO ResolveManifestGroup(groupDefinition).

        resolvedManifest:ADD(
            groupName,
            LEXICON(
                "definition", groupDefinition,
                "parts", resolvedParts,
                "is_valid", ValidateManifestGroup(groupDefinition, resolvedParts)
            )
        ).
    }.

    RETURN resolvedManifest.
}.

GLOBAL FUNCTION ExecuteManifestGroup {
    PARAMETER resolvedGroup.

    LOCAL groupDefinition TO resolvedGroup["definition"].
    LOCAL resolvedParts TO resolvedGroup["parts"].
    LOCAL triggerType TO groupDefinition["trigger_type"].
    LOCAL triggerName TO groupDefinition["trigger_name"].
    LOCAL moduleName TO "".
    LOCAL triggerValue TO TRUE.

    IF groupDefinition:HASKEY("module_name") {
        SET moduleName TO groupDefinition["module_name"].
    }.

    IF groupDefinition:HASKEY("trigger_value") {
        SET triggerValue TO groupDefinition["trigger_value"].
    }.

    FOR resolvedPart IN resolvedParts {
        ExecutePartTrigger(resolvedPart, triggerType, triggerName, moduleName, triggerValue).
    }.
}.

GLOBAL FUNCTION ExecutePartTrigger {
    PARAMETER part, triggerType, triggerName, moduleName, triggerValue.

    IF moduleName <> "" {
        IF part:HASMODULE(moduleName) {
            LOCAL selectedModule TO part:GETMODULE(moduleName).

            IF triggerType = "module_event" AND selectedModule:HASEVENT(triggerName) {
                selectedModule:DOEVENT(triggerName).
            } ELSE IF triggerType = "module_action" AND selectedModule:HASACTION(triggerName) {
                selectedModule:DOACTION(triggerName, triggerValue).
            }.

            RETURN.
        }.
    }.

    FOR availableModuleName IN part:MODULES {
        LOCAL availableModule TO part:GETMODULE(availableModuleName).

        IF triggerType = "module_event" AND availableModule:HASEVENT(triggerName) {
            availableModule:DOEVENT(triggerName).
            RETURN.
        }.

        IF triggerType = "module_action" AND availableModule:HASACTION(triggerName) {
            availableModule:DOACTION(triggerName, triggerValue).
            RETURN.
        }.
    }.
}.
