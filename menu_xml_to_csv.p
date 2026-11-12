/*------------------------------------------------------------------------
    File        : menu_xml_to_csv.p
    Purpose     : Quick DCR. Import a MIP menu XML export and write a CSV
                  of the menu tree so administrators can read the structure
                  and prep security roles.

    Description : The import frame takes the XML path and a root menu code
                  (default eb_Main). The program reads ws_menu and mi_object
                  from the dsMIP document, walks each menu and its sub-menus,
                  and writes the CSV to SESSION:TEMP-DIRECTORY.

                  The Extract Done message shows the full path and filename.

                  MenuPath is the label breadcrumb from the top of the tree.
                  MenuCodePath is the same breadcrumb using menu codes, which
                  stays unique when two items share a label. ObjectCode is
                  the wob an administrator secures. DisplayRule and ActiveRule
                  are the menu rules that hide or disable the item.

    Run         : RUN menu_xml_to_csv.p.

    Input       : A dsMIP WRITE-XML export. The file is copied into a LONGCHAR
                  and read with READ-XML into ws_menu and mi_object. A control
                  character in an unrelated table is replaced first so the
                  document stays well-formed.
  ----------------------------------------------------------------------*/

DEFINE VARIABLE cXmlFile    AS CHARACTER NO-UNDO FORMAT "x(52)".
DEFINE VARIABLE cRootMenu   AS CHARACTER NO-UNDO FORMAT "x(40)" INITIAL "eb_Main".
DEFINE VARIABLE gcFail      AS CHARACTER NO-UNDO.
DEFINE VARIABLE gcOutFile   AS CHARACTER NO-UNDO.
DEFINE VARIABLE glcCsv      AS LONGCHAR  NO-UNDO.
DEFINE VARIABLE giRows      AS INTEGER   NO-UNDO.

DEFINE BUTTON btn_extract LABEL "Extract".
DEFINE BUTTON btn_browse  LABEL "Browse".
DEFINE BUTTON btn_exit    LABEL "Exit" AUTO-ENDKEY.

/* The path separator is a scoped value so the breadcrumb stays consistent. */
&SCOPED-DEFINE PATH-SEP " > "

DEFINE TEMP-TABLE ws_menu NO-UNDO
    FIELD menu_obj          AS DECIMAL DECIMALS 9
    FIELD application_key   AS CHARACTER
    FIELD object_obj        AS DECIMAL DECIMALS 9
    FIELD parent_menu_obj   AS DECIMAL DECIMALS 9
    FIELD menu_sequence     AS INT64
    FIELD menu_code         AS CHARACTER
    FIELD menu_label        AS CHARACTER
    FIELD menu_description  AS CHARACTER
    FIELD menu_attributes   AS CHARACTER
    FIELD menu_rule_display        AS CHARACTER
    FIELD menu_rule_active         AS CHARACTER
    FIELD menu_rule_format         AS CHARACTER
    FIELD menu_link_type           AS CHARACTER
    FIELD menu_expanded            AS CHARACTER
    FIELD menu_image_set           AS CHARACTER
    FIELD menu_allow_double_submit AS CHARACTER
    INDEX idx_menu menu_obj
    INDEX idx_parent parent_menu_obj menu_sequence menu_label menu_code
    INDEX idx_code menu_code.

DEFINE TEMP-TABLE mi_object NO-UNDO
    FIELD object_obj             AS DECIMAL DECIMALS 9
    FIELD application_key        AS CHARACTER
    FIELD type_acronym_key       AS CHARACTER
    FIELD category_key           AS CHARACTER
    FIELD object_code            AS CHARACTER
    FIELD object_label           AS CHARACTER
    FIELD object_description     AS CHARACTER
    FIELD object_path            AS CHARACTER
    FIELD object_filename        AS CHARACTER
    FIELD object_stack           AS CHARACTER
    FIELD object_attributes      AS CHARACTER
    FIELD object_remote_url      AS CHARACTER
    FIELD object_requires_session AS CHARACTER
    FIELD markdown_help_filename AS CHARACTER
    INDEX idx_obj object_obj.

/* The export also contains these tables. They are loaded so READ-XML can
   accept the whole dsMIP document. The CSV uses ws_menu and mi_object. */
DEFINE TEMP-TABLE mi_parameter NO-UNDO
    FIELD parameter_key              AS CHARACTER
    FIELD category_key               AS CHARACTER
    FIELD parameter_code             AS CHARACTER
    FIELD parameter_label            AS CHARACTER
    FIELD parameter_description      AS CHARACTER
    FIELD parameter_default_value    AS CHARACTER
    FIELD parameter_documentation    AS CHARACTER
    FIELD preference_search_sequence AS CHARACTER
    FIELD value_refmaster_namelist   AS CHARACTER
    FIELD value_format_expression    AS CHARACTER
    FIELD value_validation_expression AS CHARACTER.

DEFINE TEMP-TABLE mi_message NO-UNDO
    FIELD message_obj            AS CHARACTER
    FIELD category_key           AS CHARACTER
    FIELD message_number         AS CHARACTER
    FIELD message_type           AS CHARACTER
    FIELD message_text           AS CHARACTER
    FIELD message_description    AS CHARACTER
    FIELD message_help           AS CHARACTER
    FIELD status_key             AS CHARACTER
    FIELD language_key           AS CHARACTER
    FIELD markdown_help_filename AS CHARACTER.

DEFINE TEMP-TABLE mi_category NO-UNDO
    FIELD category_key           AS CHARACTER
    FIELD category_structure_key AS CHARACTER
    FIELD parent_category_key    AS CHARACTER
    FIELD category_root_type     AS CHARACTER
    FIELD category_sequence      AS CHARACTER
    FIELD category_level         AS CHARACTER
    FIELD category_code          AS CHARACTER
    FIELD category_label         AS CHARACTER
    FIELD category_description   AS CHARACTER
    FIELD category_value         AS CHARACTER
    FIELD category_rule_active   AS CHARACTER
    FIELD category_rule_display  AS CHARACTER
    FIELD category_rule_format   AS CHARACTER
    FIELD category_wob_namelist  AS CHARACTER
    FIELD structure_ref_value    AS CHARACTER.

DEFINE TEMP-TABLE mi_preference NO-UNDO
    FIELD preference_obj         AS CHARACTER
    FIELD parameter_key          AS CHARACTER
    FIELD preference_context     AS CHARACTER
    FIELD owning_entity_mnemonic AS CHARACTER
    FIELD owning_obj             AS CHARACTER
    FIELD owning_key             AS CHARACTER
    FIELD preference_value       AS CHARACTER
    FIELD effective_from_datetime AS CHARACTER
    FIELD effective_to_datetime  AS CHARACTER.

DEFINE TEMP-TABLE mi_application NO-UNDO
    FIELD application_key          AS CHARACTER
    FIELD status_key               AS CHARACTER
    FIELD application_code         AS CHARACTER
    FIELD application_label        AS CHARACTER
    FIELD application_description  AS CHARACTER
    FIELD application_tag          AS CHARACTER
    FIELD application_is_standalone AS CHARACTER.

DEFINE TEMP-TABLE entity_lookup NO-UNDO
    FIELD entity_mnemonic AS CHARACTER
    FIELD entity_obj      AS CHARACTER
    FIELD entity_key      AS CHARACTER
    FIELD entity_lookup   AS CHARACTER.

DEFINE DATASET dsMIP FOR
    ws_menu, mi_object, mi_parameter, mi_message, mi_category,
    mi_preference, mi_application, entity_lookup.

DEFINE TEMP-TABLE tt-visit NO-UNDO
    FIELD menu_obj AS DECIMAL DECIMALS 9
    INDEX idx_visit IS UNIQUE menu_obj.

FUNCTION csvCell   RETURNS CHARACTER (INPUT pcValue AS CHARACTER) FORWARD.
FUNCTION csvHeader RETURNS CHARACTER () FORWARD.
FUNCTION fmtObj    RETURNS CHARACTER (INPUT pdValue AS DECIMAL) FORWARD.
FUNCTION safeToken RETURNS CHARACTER (INPUT pcValue AS CHARACTER) FORWARD.
FUNCTION tempDirectory RETURNS CHARACTER () FORWARD.
FUNCTION itemType  RETURNS CHARACTER
    (INPUT pcLink AS CHARACTER,
     INPUT piKids AS INTEGER,
     INPUT plHasObject AS LOGICAL) FORWARD.
FUNCTION childCount RETURNS INTEGER (INPUT pdParent AS DECIMAL) FORWARD.
FUNCTION programPath RETURNS CHARACTER
    (INPUT pcPath AS CHARACTER, INPUT pcFile AS CHARACTER) FORWARD.

FORM
    SKIP(1)
    cXmlFile COLON 18 LABEL "XML File"
        HELP "Full path of the MIP menu XML export"
    SKIP
    cRootMenu COLON 18 LABEL "Root Menu"
        HELP "Menu code to export. Leave blank to export every top-level menu."
    SKIP(1)
    btn_extract AT 18
    btn_browse  AT 34
    btn_exit    AT 50
    SKIP(1)
    "Extract writes a CSV to the session temp directory." AT 4
    SKIP
    "Root Menu defaults to eb_Main. Leave it blank to export every root." AT 4
    SKIP(1)
    WITH FRAME f-import
        SIDE-LABELS
        CENTERED
        OVERLAY
        TITLE " Import Menu XML "
        ROW 2
        WIDTH 78.

ON RETURN OF cRootMenu IN FRAME f-import DO:
    APPLY "CHOOSE" TO btn_extract IN FRAME f-import.
    RETURN NO-APPLY.
END.

ON CHOOSE OF btn_browse IN FRAME f-import DO:
    /* Stay on the import frame so a cancelled browse does not extract. */
    RUN browseForXml.
    RETURN NO-APPLY.
END.

IF SESSION:BATCH-MODE THEN DO:
    MESSAGE
        "menu_xml_to_csv.p runs from a GUI or character client." SKIP
        "Choose the XML on the import frame, then press Extract."
        VIEW-AS ALERT-BOX ERROR TITLE "Import Menu XML".
    RETURN.
END.

REPEAT
    ON ERROR  UNDO, NEXT
    ON ENDKEY UNDO, LEAVE
    ON STOP   UNDO, LEAVE
    ON QUIT   UNDO, LEAVE:

    UPDATE cXmlFile cRootMenu btn_extract btn_browse btn_exit
        WITH FRAME f-import.

    RUN runExtract (INPUT cXmlFile, INPUT cRootMenu).

    IF gcFail <> "" THEN
        MESSAGE gcFail
            VIEW-AS ALERT-BOX ERROR TITLE "Import Menu XML".
    ELSE
        MESSAGE
            "Extract Done:" SKIP
            gcOutFile SKIP
            STRING(giRows) "menu rows."
            VIEW-AS ALERT-BOX INFORMATION TITLE "Extract Done".
END.

/*------------------------------------------------------------------------
    Import frame actions and the extract itself.
  ----------------------------------------------------------------------*/

PROCEDURE browseForXml:
/* Let the user pick the XML. Character clients type the path instead. */
    DEFINE VARIABLE cFile AS CHARACTER NO-UNDO.
    DEFINE VARIABLE lOk   AS LOGICAL   NO-UNDO.

    IF SESSION:WINDOW-SYSTEM = "TTY" THEN DO:
        MESSAGE
            "Type the full XML path." SKIP
            "Browse is available in a GUI session."
            VIEW-AS ALERT-BOX INFORMATION TITLE "Import Menu XML".
        RETURN.
    END.

    SYSTEM-DIALOG GET-FILE cFile
        TITLE "Select menu XML export"
        FILTERS "XML files (*.xml)" "*.xml", "All files (*.*)" "*.*"
        DEFAULT-EXTENSION ".xml"
        MUST-EXIST
        USE-FILENAME
        UPDATE lOk.

    IF lOk = TRUE AND cFile <> "" THEN DO:
        cXmlFile = cFile.
        cXmlFile:SCREEN-VALUE IN FRAME f-import = cFile.
        DISPLAY cXmlFile WITH FRAME f-import.
    END.
END PROCEDURE.

PROCEDURE runExtract:
/* Read the XML and write the menu CSV to the session temp directory. */
    DEFINE INPUT PARAMETER pcXmlFile AS CHARACTER NO-UNDO.
    DEFINE INPUT PARAMETER pcRoot    AS CHARACTER NO-UNDO.

    DEFINE VARIABLE cOut    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iMenus  AS INTEGER   NO-UNDO.
    DEFINE BUFFER bCount FOR ws_menu.

    gcFail = "".
    gcOutFile = "".
    giRows = 0.
    glcCsv = "".
    EMPTY TEMP-TABLE ws_menu.
    EMPTY TEMP-TABLE mi_object.
    EMPTY TEMP-TABLE tt-visit.

    pcXmlFile = TRIM(pcXmlFile).
    pcRoot = TRIM(pcRoot).

    IF pcXmlFile = "" THEN DO:
        gcFail = "Enter the XML file to import.".
        RETURN.
    END.

    FILE-INFO:FILE-NAME = pcXmlFile.
    IF FILE-INFO:FULL-PATHNAME = ?
       OR FILE-INFO:FILE-TYPE = ?
       OR INDEX(FILE-INFO:FILE-TYPE, "F") = 0 THEN DO:
        gcFail = "XML file not found: " + pcXmlFile.
        RETURN.
    END.
    pcXmlFile = FILE-INFO:FULL-PATHNAME.

    RUN loadMenuXml (INPUT pcXmlFile).
    IF gcFail <> "" THEN RETURN.

    FOR EACH bCount:
        iMenus = iMenus + 1.
    END.
    IF iMenus = 0 THEN DO:
        gcFail = "No ws_menu records were found in the XML. "
               + "The file should be a dsMIP menu export.".
        RETURN.
    END.

    IF pcRoot <> ""
       AND NOT CAN-FIND(FIRST ws_menu WHERE ws_menu.menu_code = pcRoot) THEN DO:
        gcFail = "Root menu '" + pcRoot + "' was not found. "
               + STRING(iMenus) + " menus were read. "
               + "Leave Root Menu blank to export every top-level menu.".
        RETURN.
    END.

    cOut = tempDirectory()
         + "menu-"
         + safeToken(pcRoot)
         + "-"
         + STRING(YEAR(TODAY), "9999")
         + STRING(MONTH(TODAY), "99")
         + STRING(DAY(TODAY), "99")
         + "-"
         + REPLACE(STRING(TIME, "HH:MM:SS"), ":", "")
         + ".csv".

    glcCsv = csvHeader() + CHR(13) + CHR(10).
    RUN writeTree (INPUT pcRoot).
    RUN writeUtf8File (INPUT cOut, INPUT glcCsv).
    IF gcFail <> "" THEN RETURN.

    FILE-INFO:FILE-NAME = cOut.
    IF FILE-INFO:FULL-PATHNAME = ? THEN DO:
        gcFail = "The CSV was not created.".
        RETURN.
    END.

    gcOutFile = FILE-INFO:FULL-PATHNAME.
END PROCEDURE.

PROCEDURE loadMenuXml:
/* Copy the export into a LONGCHAR and READ-XML it into dsMIP. */
    DEFINE INPUT PARAMETER pcFile AS CHARACTER NO-UNDO.

    DEFINE VARIABLE lcXml AS LONGCHAR NO-UNDO.
    DEFINE VARIABLE iChar AS INTEGER  NO-UNDO.
    DEFINE VARIABLE lOk   AS LOGICAL  NO-UNDO.

    COPY-LOB FROM FILE pcFile TO lcXml NO-ERROR.
    IF ERROR-STATUS:ERROR OR lcXml = ? THEN DO:
        gcFail = "Could not read the XML file.".
        IF ERROR-STATUS:NUM-MESSAGES > 0 THEN
            gcFail = gcFail + " " + ERROR-STATUS:GET-MESSAGE(1).
        RETURN.
    END.

    /* This export can contain a control character outside the menu tables.
       XML 1.0 allows only tab, LF and CR below space. */
    DO iChar = 1 TO 31:
        IF iChar = 9 OR iChar = 10 OR iChar = 13 THEN NEXT.
        IF INDEX(lcXml, CHR(iChar)) > 0 THEN
            lcXml = REPLACE(lcXml, CHR(iChar), " ").
    END.

    lOk = DATASET dsMIP:READ-XML("LONGCHAR", lcXml, "EMPTY", ?, ?, ?, ?) NO-ERROR.
    IF lOk <> TRUE OR ERROR-STATUS:ERROR THEN DO:
        gcFail = "Could not read the menu XML.".
        IF ERROR-STATUS:NUM-MESSAGES > 0 THEN
            gcFail = gcFail + " " + ERROR-STATUS:GET-MESSAGE(1).
    END.
END PROCEDURE.

PROCEDURE writeTree:
/* Export one root menu, or every top-level menu when the root is blank. */
    DEFINE INPUT PARAMETER pcRoot AS CHARACTER NO-UNDO.

    DEFINE BUFFER bRoot   FOR ws_menu.
    DEFINE BUFFER bParent FOR ws_menu.

    IF pcRoot <> "" THEN DO:
        FOR EACH bRoot
            WHERE bRoot.menu_code = pcRoot
            BY bRoot.menu_sequence
            BY bRoot.menu_label
            BY bRoot.menu_code:
            RUN walkMenu (INPUT bRoot.menu_obj, INPUT 1).
        END.
        RETURN.
    END.

    FOR EACH bRoot
        WHERE bRoot.parent_menu_obj = 0
        BY bRoot.menu_sequence
        BY bRoot.menu_label
        BY bRoot.menu_code:
        RUN walkMenu (INPUT bRoot.menu_obj, INPUT 1).
    END.

    /* A menu whose parent is not in the file still needs a row. */
    FOR EACH bRoot
        WHERE bRoot.parent_menu_obj <> 0
        BY bRoot.menu_sequence
        BY bRoot.menu_label
        BY bRoot.menu_code:
        IF CAN-FIND(FIRST bParent
                    WHERE bParent.menu_obj = bRoot.parent_menu_obj) THEN NEXT.
        RUN walkMenu (INPUT bRoot.menu_obj, INPUT 1).
    END.
END PROCEDURE.

PROCEDURE walkMenu:
/* Preorder walk so a parent row is followed by its sub-menus. */
    DEFINE INPUT PARAMETER pdMenu  AS DECIMAL NO-UNDO.
    DEFINE INPUT PARAMETER piDepth AS INTEGER NO-UNDO.

    DEFINE BUFFER bMenu  FOR ws_menu.
    DEFINE BUFFER bChild FOR ws_menu.

    IF piDepth > 40 THEN RETURN.
    IF CAN-FIND(tt-visit WHERE tt-visit.menu_obj = pdMenu) THEN RETURN.

    FIND bMenu WHERE bMenu.menu_obj = pdMenu NO-ERROR.
    IF NOT AVAILABLE bMenu THEN RETURN.

    CREATE tt-visit.
    ASSIGN tt-visit.menu_obj = pdMenu.

    RUN writeMenuRow (INPUT pdMenu).

    FOR EACH bChild
        WHERE bChild.parent_menu_obj = pdMenu
        BY bChild.menu_sequence
        BY bChild.menu_label
        BY bChild.menu_code:
        RUN walkMenu (INPUT bChild.menu_obj, INPUT piDepth + 1).
    END.
END PROCEDURE.

PROCEDURE writeMenuRow:
/* One CSV row. MenuPath always starts at the top of the tree. */
    DEFINE INPUT PARAMETER pdMenu AS DECIMAL NO-UNDO.

    DEFINE VARIABLE cLabelPath AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cCodePath  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iLevel     AS INTEGER   NO-UNDO.
    DEFINE VARIABLE iKids      AS INTEGER   NO-UNDO.
    DEFINE VARIABLE cParent    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cProgram   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cObjCode   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cObjLabel  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cObjDesc   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cLine      AS CHARACTER NO-UNDO.
    DEFINE VARIABLE lHasObject AS LOGICAL   NO-UNDO.

    DEFINE BUFFER bMenu   FOR ws_menu.
    DEFINE BUFFER bParent FOR ws_menu.
    DEFINE BUFFER bObj    FOR mi_object.

    FIND bMenu WHERE bMenu.menu_obj = pdMenu NO-ERROR.
    IF NOT AVAILABLE bMenu THEN RETURN.

    RUN nodePath (INPUT bMenu.menu_obj,
                  OUTPUT cLabelPath,
                  OUTPUT cCodePath,
                  OUTPUT iLevel).

    FIND bParent WHERE bParent.menu_obj = bMenu.parent_menu_obj NO-ERROR.
    IF AVAILABLE bParent THEN cParent = bParent.menu_code.

    iKids = childCount(bMenu.menu_obj).
    lHasObject = bMenu.object_obj <> 0 AND bMenu.object_obj <> ?.

    IF lHasObject THEN DO:
        FIND bObj WHERE bObj.object_obj = bMenu.object_obj NO-ERROR.
        IF AVAILABLE bObj THEN DO:
            ASSIGN
                cObjCode  = bObj.object_code
                cObjLabel = bObj.object_label
                cObjDesc  = bObj.object_description
                cProgram  = programPath(bObj.object_path, bObj.object_filename).
        END.
    END.

    cLine = csvCell(cLabelPath) + ","
          + csvCell(STRING(iLevel)) + ","
          + csvCell(STRING(bMenu.menu_sequence)) + ","
          + csvCell(bMenu.menu_code) + ","
          + csvCell(bMenu.menu_label) + ","
          + csvCell(bMenu.menu_description) + ","
          + csvCell(bMenu.menu_link_type) + ","
          + csvCell(itemType(bMenu.menu_link_type, iKids, lHasObject)) + ","
          + csvCell(cParent) + ","
          + csvCell(STRING(iKids)) + ","
          + csvCell(bMenu.application_key) + ","
          + csvCell(cObjCode) + ","
          + csvCell(cObjLabel) + ","
          + csvCell(cObjDesc) + ","
          + csvCell(cProgram) + ","
          + csvCell(bMenu.menu_rule_display) + ","
          + csvCell(bMenu.menu_rule_active) + ","
          + csvCell(bMenu.menu_attributes) + ","
          + csvCell(cCodePath) + ","
          + csvCell(fmtObj(bMenu.menu_obj)) + ","
          + csvCell(fmtObj(bMenu.parent_menu_obj)) + ","
          + csvCell(fmtObj(bMenu.object_obj)).

    glcCsv = glcCsv + cLine + CHR(13) + CHR(10).
    giRows = giRows + 1.
END PROCEDURE.

PROCEDURE nodePath:
/* Walk parents so the breadcrumb includes ancestors above the start menu. */
    DEFINE INPUT  PARAMETER pdStart     AS DECIMAL   NO-UNDO.
    DEFINE OUTPUT PARAMETER pcLabelPath AS CHARACTER NO-UNDO.
    DEFINE OUTPUT PARAMETER pcCodePath  AS CHARACTER NO-UNDO.
    DEFINE OUTPUT PARAMETER piLevel     AS INTEGER   NO-UNDO.

    DEFINE VARIABLE dCurr AS DECIMAL   NO-UNDO.
    DEFINE VARIABLE cSeen AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cId   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cLabel AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cCode  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iGuard AS INTEGER  NO-UNDO.

    DEFINE BUFFER bNode FOR ws_menu.

    ASSIGN
        dCurr       = pdStart
        cSeen       = ","
        pcLabelPath = ""
        pcCodePath  = ""
        piLevel     = 0.

    DO WHILE dCurr <> 0 AND dCurr <> ? AND iGuard < 50:
        FIND bNode WHERE bNode.menu_obj = dCurr NO-ERROR.
        IF NOT AVAILABLE bNode THEN LEAVE.

        cId = fmtObj(bNode.menu_obj).
        IF cId <> "" AND INDEX(cSeen, "," + cId + ",") > 0 THEN LEAVE.
        cSeen = cSeen + cId + ",".

        cLabel = TRIM(bNode.menu_label).
        IF cLabel = "" THEN cLabel = TRIM(bNode.menu_code).
        cCode = TRIM(bNode.menu_code).

        piLevel = piLevel + 1.
        IF pcLabelPath = "" THEN
            ASSIGN
                pcLabelPath = cLabel
                pcCodePath  = cCode.
        ELSE
            ASSIGN
                pcLabelPath = cLabel + {&PATH-SEP} + pcLabelPath
                pcCodePath  = cCode + {&PATH-SEP} + pcCodePath.

        dCurr = bNode.parent_menu_obj.
        iGuard = iGuard + 1.
    END.
END PROCEDURE.

PROCEDURE writeUtf8File:
/* Write the CSV as UTF-8 with a BOM so Excel keeps the text intact. */
    DEFINE INPUT PARAMETER pcFile AS CHARACTER NO-UNDO.
    DEFINE INPUT PARAMETER plcText AS LONGCHAR NO-UNDO.

    DEFINE VARIABLE mBody AS MEMPTR NO-UNDO.
    DEFINE VARIABLE mAll  AS MEMPTR NO-UNDO.
    DEFINE VARIABLE iSize AS INT64  NO-UNDO.
    DEFINE VARIABLE iPos  AS INT64  NO-UNDO.

    COPY-LOB FROM plcText TO mBody CONVERT TARGET CODEPAGE "UTF-8" NO-ERROR.
    IF ERROR-STATUS:ERROR THEN DO:
        gcFail = "Could not encode the CSV: " + ERROR-STATUS:GET-MESSAGE(1).
        SET-SIZE(mBody) = 0.
        RETURN.
    END.

    iSize = GET-SIZE(mBody).
    SET-SIZE(mAll) = iSize + 3.
    PUT-BYTE(mAll, 1) = 239.
    PUT-BYTE(mAll, 2) = 187.
    PUT-BYTE(mAll, 3) = 191.

    DO iPos = 1 TO iSize:
        PUT-BYTE(mAll, iPos + 3) = GET-BYTE(mBody, iPos).
    END.

    COPY-LOB FROM mAll TO FILE pcFile NO-ERROR.
    IF ERROR-STATUS:ERROR THEN
        gcFail = "Could not create the CSV in the temp directory: "
               + ERROR-STATUS:GET-MESSAGE(1).

    SET-SIZE(mBody) = 0.
    SET-SIZE(mAll) = 0.
END PROCEDURE.

/*------------------------------------------------------------------------
    CSV helpers.
  ----------------------------------------------------------------------*/

FUNCTION csvHeader RETURNS CHARACTER ():
/* Column order is the order administrators see when they open the file.
   MenuPath is the readable tree. ObjectCode is the wob to secure. */
    RETURN "MenuPath,Level,MenuSequence,MenuCode,MenuLabel,MenuDescription,"
         + "LinkType,ItemType,ParentMenuCode,ChildCount,Application,"
         + "ObjectCode,ObjectLabel,ObjectDescription,ProgramPath,"
         + "DisplayRule,ActiveRule,MenuAttributes,MenuCodePath,"
         + "MenuObj,ParentMenuObj,ObjectObj".
END FUNCTION.

FUNCTION csvCell RETURNS CHARACTER (INPUT pcValue AS CHARACTER):
/* Quote a value when Excel or a comma would split it. */
    IF pcValue = ? THEN pcValue = "".
    pcValue = REPLACE(pcValue, '"', '""').
    IF INDEX(pcValue, '"') > 0
       OR INDEX(pcValue, ",") > 0
       OR INDEX(pcValue, CHR(10)) > 0
       OR INDEX(pcValue, CHR(13)) > 0 THEN
        RETURN '"' + pcValue + '"'.
    RETURN pcValue.
END FUNCTION.

FUNCTION itemType RETURNS CHARACTER
    (INPUT pcLink AS CHARACTER,
     INPUT piKids AS INTEGER,
     INPUT plHasObject AS LOGICAL):
/* A short type administrators can filter on. LinkType keeps the raw value. */
    IF pcLink = "WOB" THEN DO:
        IF piKids > 0 THEN RETURN "Program with sub-menus".
        RETURN "Program".
    END.
    IF plHasObject THEN RETURN "Folder with program".
    RETURN "Folder".
END FUNCTION.

FUNCTION childCount RETURNS INTEGER (INPUT pdParent AS DECIMAL):
    DEFINE VARIABLE iCount AS INTEGER NO-UNDO.
    DEFINE BUFFER bChild FOR ws_menu.

    FOR EACH bChild WHERE bChild.parent_menu_obj = pdParent:
        iCount = iCount + 1.
    END.
    RETURN iCount.
END FUNCTION.

FUNCTION programPath RETURNS CHARACTER
    (INPUT pcPath AS CHARACTER, INPUT pcFile AS CHARACTER):
/* object_path plus object_filename, with a single slash between them. */
    pcPath = REPLACE(TRIM(pcPath), CHR(92), "/").
    pcFile = REPLACE(TRIM(pcFile), CHR(92), "/").
    IF pcPath <> "" AND pcFile <> "" THEN
        RETURN RIGHT-TRIM(pcPath, "/") + "/" + LEFT-TRIM(pcFile, "/").
    RETURN pcPath + pcFile.
END FUNCTION.

FUNCTION fmtObj RETURNS CHARACTER (INPUT pdValue AS DECIMAL):
/* Menu and object ids are whole numbers in the export. Blank means none. */
    IF pdValue = ? OR pdValue = 0 THEN RETURN "".
    RETURN TRIM(STRING(TRUNCATE(pdValue, 0), ">>>>>>>>>>>>>>>>>9")).
END FUNCTION.

FUNCTION safeToken RETURNS CHARACTER (INPUT pcValue AS CHARACTER):
/* A filename piece made from the root menu code. */
    DEFINE VARIABLE cOut AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cCh  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iPos AS INTEGER   NO-UNDO.

    pcValue = LC(TRIM(pcValue)).
    IF pcValue = "" THEN RETURN "all".

    DO iPos = 1 TO LENGTH(pcValue):
        cCh = SUBSTRING(pcValue, iPos, 1).
        IF INDEX("abcdefghijklmnopqrstuvwxyz0123456789_-", cCh) > 0 THEN
            cOut = cOut + cCh.
        ELSE
            cOut = cOut + "-".
    END.

    DO WHILE INDEX(cOut, "--") > 0:
        cOut = REPLACE(cOut, "--", "-").
    END.
    cOut = TRIM(cOut, "-").
    IF cOut = "" THEN RETURN "menu".
    RETURN cOut.
END FUNCTION.

FUNCTION tempDirectory RETURNS CHARACTER ():
/* SESSION:TEMP-DIRECTORY with exactly one trailing slash. */
    DEFINE VARIABLE cDir   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cLast  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSlash AS CHARACTER NO-UNDO.

    cSlash = IF OPSYS BEGINS "WIN" THEN CHR(92) ELSE "/".
    cDir = SESSION:TEMP-DIRECTORY.
    IF cDir = ? OR TRIM(cDir) = "" THEN cDir = ".".
    cLast = SUBSTRING(cDir, LENGTH(cDir), 1).
    IF cLast <> "/" AND cLast <> CHR(92) THEN
        cDir = cDir + cSlash.
    RETURN cDir.
END FUNCTION.
