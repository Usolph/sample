BLOCK-LEVEL ON ERROR UNDO, THROW.
/*------------------------------------------------------------------------
  12/11/2026    Usolph Mamaila
  - DCR to turn a MIP menu XML export into CSV files for security role prep
  - One CSV per root menu. Leave Root Menu blank when the export has every menu
  ----------------------------------------------------------------------*/
/* **********************************************  Definitions  *********************************************** */
  {mip/inc/mipdefshared.i}

  /* Variables .........................................................................................................*/
  DEFINE VARIABLE lOk                        AS LOGICAL                                                    NO-UNDO.
  DEFINE VARIABLE iCount                     AS INTEGER                                                    NO-UNDO.
  DEFINE VARIABLE giRows                     AS INTEGER                                                    NO-UNDO.
  DEFINE VARIABLE cImportFile                AS CHARACTER  VIEW-AS FILL-IN SIZE 100 BY 1 FORMAT "x(200)"   NO-UNDO.
  DEFINE VARIABLE cFile                      AS CHARACTER  VIEW-AS FILL-IN SIZE 100 BY 1 FORMAT "x(200)"   NO-UNDO.
  DEFINE VARIABLE cFilename                  AS CHARACTER                                                  NO-UNDO.
  DEFINE VARIABLE cRootMenu                  AS CHARACTER  VIEW-AS FILL-IN SIZE 40 BY 1 FORMAT "x(80)"     NO-UNDO.
  DEFINE VARIABLE cMipLog                    AS CHARACTER                                                  NO-UNDO.
  DEFINE VARIABLE cTargetDir                 AS CHARACTER                                                  NO-UNDO.
  DEFINE VARIABLE gcFail                     AS CHARACTER                                                  NO-UNDO.
  DEFINE VARIABLE gcWritten                  AS CHARACTER                                                  NO-UNDO.
  DEFINE VARIABLE giFiles                    AS INTEGER                                                    NO-UNDO.
  DEFINE VARIABLE glCheckingDir              AS LOGICAL                                                    NO-UNDO.
  DEFINE VARIABLE glcCsv                     AS LONGCHAR                                                   NO-UNDO.

  /* Frames ............................................................................................................*/
  DEFINE BUTTON BuFind
    LABEL "&Find..."
    SIZE 14 BY 1.14
    BGCOLOR 8.
  DEFINE BUTTON BuExtract
    LABEL "&Extract"
    SIZE 14 BY 1.14
    BGCOLOR 8.

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

/* One row per CSV. A full export writes a file for every root menu. */
DEFINE TEMP-TABLE tt-export NO-UNDO
    FIELD iSeq      AS INTEGER
    FIELD menu_code AS CHARACTER
    FIELD menu_obj  AS DECIMAL DECIMALS 9
    FIELD cOutFile  AS CHARACTER
    FIELD iRows     AS INTEGER
    INDEX idx_seq iSeq.

FUNCTION csvCell   RETURNS CHARACTER (INPUT pcValue AS CHARACTER) FORWARD.
FUNCTION csvHeader RETURNS CHARACTER () FORWARD.
FUNCTION fmtObj    RETURNS CHARACTER (INPUT pdValue AS DECIMAL) FORWARD.
FUNCTION safeToken RETURNS CHARACTER (INPUT pcValue AS CHARACTER) FORWARD.
FUNCTION dirWithSlash RETURNS CHARACTER (INPUT pcDir AS CHARACTER) FORWARD.
FUNCTION outputDirStatus RETURNS CHARACTER
    (INPUT pcDir AS CHARACTER, OUTPUT pcClean AS CHARACTER) FORWARD.
FUNCTION itemType  RETURNS CHARACTER
    (INPUT pcLink AS CHARACTER,
     INPUT piKids AS INTEGER,
     INPUT plHasObject AS LOGICAL) FORWARD.
FUNCTION childCount RETURNS INTEGER (INPUT pdParent AS DECIMAL) FORWARD.
FUNCTION programPath RETURNS CHARACTER
    (INPUT pcPath AS CHARACTER, INPUT pcFile AS CHARACTER) FORWARD.

  DEFINE FRAME main-frame
    "Input File:"        AT ROW 3.4   COL 3  VIEW-AS TEXT cImportFile           AT ROW 3.1   COL 25 NO-LABEL
     BuFind              AT ROW 3.0   COL 130
    "Root Menu:"         AT ROW 5.4   COL 3  VIEW-AS TEXT cRootMenu              AT ROW 5.1   COL 25 NO-LABEL
                         HELP "Optional. Leave blank to write one CSV for each root menu."
    "Output Directory:"  AT ROW 7.4   COL 3  VIEW-AS TEXT cFile                  AT ROW 7.1   COL 25 NO-LABEL
                         HELP "Checked when you leave the field. The folder has to exist."
     BuExtract           AT ROW 7.1   COL 130
    "Leave Root Menu blank to write one CSV for each root menu." AT ROW 9.4 COL 3
                         VIEW-AS TEXT SIZE 140 BY 1
    "MenuPath is the label breadcrumb. MenuCodePath is the same path in menu codes." AT ROW 10.6 COL 3
                         VIEW-AS TEXT SIZE 140 BY 1
    "The folder is checked when you leave the field. Extract runs only when that folder exists." AT ROW 11.8 COL 3
                         VIEW-AS TEXT SIZE 140 BY 1
     WITH SIDE-LABELS THREE-D
     AT COL 1 ROW 1 SCROLLABLE
     SIZE 150 BY 14
     TITLE "Menu XML to CSV"
     VIEW-AS DIALOG-BOX.

  /* Triggers ..........................................................................................................*/
  ON CHOOSE OF BuFind IN FRAME main-frame  /* Find... */
  DO:
    SYSTEM-DIALOG GET-FILE cImportFile
      TITLE      "Select menu XML export"
      FILTERS    "XML files (*.xml)" "*.xml", "All files (*.*)" "*.*"
      MUST-EXIST
      USE-FILENAME
      UPDATE lOk.

    IF lOk THEN
    DO WITH FRAME main-frame:
      ASSIGN cImportFile:SCREEN-VALUE = cImportFile.
    END.
  END.

  ON LEAVE OF cFile IN FRAME main-frame
  DO:
    DEFINE VARIABLE cClean  AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cReason AS CHARACTER NO-UNDO.

    /* Closing the dialog must not be trapped by the path check. */
    IF KEYFUNCTION(LASTKEY) = "END-ERROR":U
       OR LAST-EVENT:LABEL = "WINDOW-CLOSE":U THEN RETURN.
    IF glCheckingDir THEN RETURN NO-APPLY.

    glCheckingDir = TRUE.
    cReason = outputDirStatus(INPUT cFile:SCREEN-VALUE, OUTPUT cClean).
    IF cReason = "":U THEN
    DO:
      ASSIGN
        cFile              = cClean
        cFile:SCREEN-VALUE = cClean
        BuExtract:SENSITIVE = TRUE.
      glCheckingDir = FALSE.
      RETURN.
    END.

    ASSIGN BuExtract:SENSITIVE = FALSE.
    MESSAGE cReason SKIP
            cFile:SCREEN-VALUE
        VIEW-AS ALERT-BOX ERROR BUTTONS OK.
    glCheckingDir = FALSE.
    RETURN NO-APPLY.
  END.

  ON CHOOSE OF BuExtract IN FRAME main-frame
  DO:
    DEFINE VARIABLE cDir    AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cReason AS CHARACTER NO-UNDO.

    DO WITH FRAME main-frame:
      ASSIGN
        cImportFile
        cFile
        cRootMenu.
    END.

    ASSIGN
      cFilename = TRIM(cImportFile)
      cRootMenu = TRIM(cRootMenu)
      cFile     = TRIM(cFile).

    IF cFilename = "":U THEN
    DO:
      MESSAGE "Enter the XML file to extract.":U
          VIEW-AS ALERT-BOX ERROR BUTTONS OK.
      RETURN NO-APPLY.
    END.

    IF SEARCH(cFilename) = ? THEN
    DO:
      MESSAGE "The XML file specified can not be found.":U
          VIEW-AS ALERT-BOX ERROR BUTTONS OK.
      RETURN NO-APPLY.
    END.

    /* The leave trigger already checked this. Check again so Extract cannot run on a bad folder. */
    ASSIGN cReason = outputDirStatus(INPUT cFile, OUTPUT cDir).
    IF cReason <> "":U THEN
    DO:
      ASSIGN BuExtract:SENSITIVE = FALSE.
      MESSAGE cReason SKIP
              cFile
          VIEW-AS ALERT-BOX ERROR BUTTONS OK.
      APPLY "ENTRY" TO cFile IN FRAME main-frame.
      RETURN NO-APPLY.
    END.
    ASSIGN cFile = cDir.
    DO WITH FRAME main-frame:
      ASSIGN cFile:SCREEN-VALUE = cFile.
    END.

    SESSION:SET-WAIT-STATE("GENERAL":U).
    RUN main-code IN THIS-PROCEDURE NO-ERROR.
    IF ERROR-STATUS:ERROR OR {&ReturnValue} <> "":U THEN
    DO:
      MESSAGE "ERROR occured during EXTRACT PROCESS:":U SKIP
              IF {&ReturnValue} <> "":U THEN {&ReturnValue}
              ELSE ERROR-STATUS:GET-MESSAGE(1)
          VIEW-AS ALERT-BOX ERROR BUTTONS OK.
      SESSION:SET-WAIT-STATE("":U).
      RETURN NO-APPLY.
    END.
    SESSION:SET-WAIT-STATE("":U).

    DISPLAY cFile WITH FRAME main-frame.
    MESSAGE "Extract Done:":U SKIP
            cFile SKIP
            STRING(giFiles) " CSV files," STRING(iCount) " menu rows." SKIP(1)
            gcWritten
        VIEW-AS ALERT-BOX INFO BUTTONS OK.
  END.

  /* --- Display Q&D Full Description ---------- */
  MESSAGE "Menu XML to CSV - written by Usolph":U SKIP(1)
          "This DCR reads a dsMIP menu export and writes one CSV for each root menu.":U SKIP(1)
          "Do you want to run this DCR?":U
    VIEW-AS ALERT-BOX INFO BUTTONS YES-NO UPDATE lOk.
  IF NOT lOk THEN RETURN.

  /* --- User Login Prompt --- */
  PROMPT-FOR gsm_user.user_login_name LABEL "User Name" FORMAT "x(20)" COLON 14
             gsm_user.user_password   LABEL "Password"  FORMAT "x(20)" COLON 14 BLANK
    WITH SIDE-LABELS THREE-D FRAME f VIEW-AS DIALOG-BOX TITLE "User Authentication".

  FIND FIRST gsm_user NO-LOCK
       WHERE gsm_user.user_login_name = INPUT gsm_user.user_login_name
       AND   gsm_user.user_password   = ENCODE(INPUT gsm_user.user_password)
       AND   NOT gsm_user.DISABLED
       NO-ERROR.
  IF NOT AVAILABLE gsm_user THEN
  DO:
    MESSAGE "User authentication failed!" VIEW-AS ALERT-BOX ERROR.
    RETURN.
  END.

  /* --- Default output folder. The fill-in stays editable. ---------- */
  /* CHR(92) is the backslash. A backslash-quote :U literal does not compile. */
  ASSIGN cTargetDir = "".
  FIND FIRST pac_parameter NO-LOCK
       WHERE pac_parameter.parameter_type = "Q&D":U
         AND pac_parameter.parameter_key  = "Fix Directory":U
       NO-ERROR.
  IF AVAILABLE pac_parameter THEN
    ASSIGN cMipLog = TRIM(REPLACE(TRIM(pac_parameter.parameter_data), CHR(47), CHR(92)), CHR(92)).
  ELSE
    ASSIGN cMipLog = "".

  IF cMipLog <> "":U THEN
    ASSIGN cMipLog = cMipLog + CHR(92) + "log":U.

  /* A value is checked as soon as the field has one, and again when you leave it. */
  IF cMipLog <> "":U
     AND outputDirStatus(INPUT cMipLog, OUTPUT cTargetDir) = "":U THEN
    ASSIGN cFile = cTargetDir.
  ELSE
  IF outputDirStatus(INPUT SESSION:TEMP-DIRECTORY, OUTPUT cTargetDir) = "":U THEN
  DO:
    ASSIGN cFile = cTargetDir.
    IF cMipLog <> "":U THEN
      MESSAGE "The Q&D Fix Directory is not a folder this session can write.":U SKIP
              "Output Directory starts in the session temp directory.":U SKIP
              "Change it if the CSV files should go somewhere else.":U
          VIEW-AS ALERT-BOX INFO BUTTONS OK.
  END.
  ELSE
    ASSIGN cFile = "".

  ENABLE ALL WITH FRAME main-frame.
  DISPLAY cFile cRootMenu WITH FRAME main-frame.
  ASSIGN BuExtract:SENSITIVE = (cFile <> "":U).
  FRAME main-frame:DEFAULT-BUTTON = BuExtract:HANDLE IN FRAME main-frame.
  IF cFile = "":U THEN
  DO:
    MESSAGE "Enter a folder that exists. Extract stays unavailable until a file can be created there.":U
        VIEW-AS ALERT-BOX ERROR BUTTONS OK.
    APPLY "ENTRY" TO cFile IN FRAME main-frame.
  END.

  WAIT-FOR "GO" OF FRAME main-frame.

PROCEDURE main-code:
/* Read the XML and write one CSV per root menu into cFile. */
  DEFINE VARIABLE iMenus AS INTEGER   NO-UNDO.
  DEFINE VARIABLE iSeq   AS INTEGER   NO-UNDO.
  DEFINE VARIABLE cStamp AS CHARACTER NO-UNDO.
  DEFINE VARIABLE cOut   AS CHARACTER NO-UNDO.
  DEFINE VARIABLE cDir   AS CHARACTER NO-UNDO.
  DEFINE BUFFER bCount  FOR ws_menu.
  DEFINE BUFFER bRoot   FOR ws_menu.
  DEFINE BUFFER bParent FOR ws_menu.
  DEFINE BUFFER bTaken  FOR tt-export.

  ASSIGN
    gcFail    = "":U
    giRows    = 0
    giFiles   = 0
    iCount    = 0
    gcWritten = "":U
    glcCsv    = "".

  EMPTY TEMP-TABLE ws_menu.
  EMPTY TEMP-TABLE mi_object.
  EMPTY TEMP-TABLE tt-visit.
  EMPTY TEMP-TABLE tt-export.

  ASSIGN
    cFilename = TRIM(cFilename)
    cRootMenu = TRIM(cRootMenu)
    cDir      = dirWithSlash(cFile).

  IF cDir = "":U THEN
    RETURN ERROR "Enter the folder where the CSV files should be written.".

  RUN loadMenuXml (INPUT cFilename).
  IF gcFail <> "":U THEN
    RETURN ERROR gcFail.

  FOR EACH bCount:
    iMenus = iMenus + 1.
  END.
  IF iMenus = 0 THEN
    RETURN ERROR "No ws_menu records were found in the XML. The file should be a dsMIP menu export.".

  IF cRootMenu <> "":U THEN
  DO:
    IF NOT CAN-FIND(FIRST ws_menu WHERE ws_menu.menu_code = cRootMenu) THEN
      RETURN ERROR "Root menu '" + cRootMenu + "' is not in this file. "
                  + STRING(iMenus) + " menus were read. "
                  + "Leave Root Menu blank to write one CSV for each root menu.".

    FOR EACH bRoot
        WHERE bRoot.menu_code = cRootMenu
        BY bRoot.menu_sequence
        BY bRoot.menu_label
        BY bRoot.menu_code:
      iSeq = iSeq + 1.
      CREATE tt-export.
      ASSIGN
        tt-export.iSeq      = iSeq
        tt-export.menu_code = bRoot.menu_code
        tt-export.menu_obj  = bRoot.menu_obj.
    END.
  END.
  ELSE DO:
    /* Blank root: every top-level menu, plus any menu whose parent is not in the file. */
    FOR EACH bRoot
        WHERE bRoot.parent_menu_obj = 0
        BY bRoot.menu_sequence
        BY bRoot.menu_label
        BY bRoot.menu_code:
      iSeq = iSeq + 1.
      CREATE tt-export.
      ASSIGN
        tt-export.iSeq      = iSeq
        tt-export.menu_code = bRoot.menu_code
        tt-export.menu_obj  = bRoot.menu_obj.
    END.

    FOR EACH bRoot
        WHERE bRoot.parent_menu_obj <> 0
        BY bRoot.menu_sequence
        BY bRoot.menu_label
        BY bRoot.menu_code:
      IF CAN-FIND(FIRST bParent WHERE bParent.menu_obj = bRoot.parent_menu_obj) THEN NEXT.
      iSeq = iSeq + 1.
      CREATE tt-export.
      ASSIGN
        tt-export.iSeq      = iSeq
        tt-export.menu_code = bRoot.menu_code
        tt-export.menu_obj  = bRoot.menu_obj.
    END.
  END.

  IF NOT CAN-FIND(FIRST tt-export) THEN
    RETURN ERROR "No root menus were found in the XML.".

  cStamp = STRING(TODAY, "99999999":U)
         + REPLACE(STRING(TIME, "hh:mm:ss":U), ":":U, "":U).

  FOR EACH tt-export BY tt-export.iSeq:
    EMPTY TEMP-TABLE tt-visit.
    ASSIGN giRows = 0.
    glcCsv = csvHeader() + CHR(13) + CHR(10).
    RUN walkMenu (INPUT tt-export.menu_obj, INPUT 1).

    cOut = cDir + "menu_":U + safeToken(tt-export.menu_code) + "_":U + cStamp + ".csv":U.
    IF CAN-FIND(FIRST bTaken WHERE bTaken.cOutFile = cOut) THEN
      cOut = cDir + "menu_":U + safeToken(tt-export.menu_code) + "_":U
           + fmtObj(tt-export.menu_obj) + "_":U + cStamp + ".csv":U.
    ASSIGN tt-export.cOutFile = cOut.

    RUN writeUtf8File (INPUT cOut, INPUT glcCsv).
    IF gcFail <> "":U THEN
      RETURN ERROR gcFail.

    FILE-INFO:FILE-NAME = cOut.
    IF FILE-INFO:FULL-PATHNAME = ? THEN
      RETURN ERROR "The CSV was not created: " + cOut.

    ASSIGN
      cOut            = FILE-INFO:FULL-PATHNAME
      tt-export.iRows = giRows
      giFiles             = giFiles + 1
      iCount              = iCount + giRows
      gcWritten           = gcWritten + cOut + " (":U + STRING(giRows) + ")":U + CHR(10).
  END.

  FILE-INFO:FILE-NAME = RIGHT-TRIM(cDir, CHR(92)).
  IF FILE-INFO:FULL-PATHNAME <> ? THEN
    ASSIGN cFile = FILE-INFO:FULL-PATHNAME.
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
        gcFail = "Could not create the CSV. Change Output Directory and run Extract again. "
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

FUNCTION outputDirStatus RETURNS CHARACTER
    (INPUT pcDir AS CHARACTER, OUTPUT pcClean AS CHARACTER):
/* Blank when the folder exists and a file can be created there. Otherwise the reason. */
    DEFINE VARIABLE cProbe AS CHARACTER NO-UNDO.

    ASSIGN pcClean = dirWithSlash(pcDir).
    IF pcClean = "":U THEN
        RETURN "Enter a folder for the CSV files. The folder has to exist.".

    FILE-INFO:FILE-NAME = RIGHT-TRIM(pcClean, CHR(92)) NO-ERROR.
    IF FILE-INFO:FULL-PATHNAME = ?
       OR INDEX(FILE-INFO:FILE-TYPE, "D":U) = 0 THEN
        RETURN "That folder does not exist.".

    ASSIGN pcClean = dirWithSlash(FILE-INFO:FULL-PATHNAME).
    cProbe = pcClean + "menu_path_check_":U + STRING(ETIME) + ".tmp":U.

    OUTPUT TO VALUE(cProbe) NO-ERROR.
    IF ERROR-STATUS:ERROR THEN
        RETURN "That folder exists, but a file cannot be created there.".

    OUTPUT CLOSE.
    OS-DELETE VALUE(cProbe) NO-ERROR.
    RETURN "".
END FUNCTION.

FUNCTION dirWithSlash RETURNS CHARACTER (INPUT pcDir AS CHARACTER):
/* Folder with one trailing backslash. A pasted CSV path uses its folder. */
    DEFINE VARIABLE cDir   AS CHARACTER NO-UNDO.
    DEFINE VARIABLE cSlash AS CHARACTER NO-UNDO.
    DEFINE VARIABLE iSlash AS INTEGER   NO-UNDO.

    cSlash = CHR(92).
    cDir = REPLACE(TRIM(pcDir), CHR(47), cSlash).
    IF cDir = ? THEN RETURN "".
    cDir = RIGHT-TRIM(cDir, cSlash).
    IF cDir = "" THEN RETURN "".

    IF cDir MATCHES "*.csv":U THEN DO:
        iSlash = R-INDEX(cDir, cSlash).
        IF iSlash > 1 THEN
            cDir = SUBSTRING(cDir, 1, iSlash - 1).
        ELSE
            RETURN "".
    END.

    RETURN cDir + cSlash.
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
