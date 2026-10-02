# ==============================================================================
# Jira Workflow & Management Functions
# ==============================================================================
# Update the jira function list whenever a new external function is added to this file.

_jira_validate_env() {
  if [ -z "$JIRA_BASE_URL" ]; then
    echo "Error: JIRA_BASE_URL is not set."
    echo "Set it with: export JIRA_BASE_URL='https://jira.example.com'"
    return 1
  fi
  if [ -z "$JIRA_TOKEN" ]; then
    echo "Error: JIRA_TOKEN is not set."
    echo "Set it with: export JIRA_TOKEN='<your-token>'"
    return 1
  fi
}

_jira_list_projects() {
  curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/project" \
    | jq -r '.[]? | select(.key != null) | [.key, (.name // "")] | @tsv' 2>/dev/null
}

jira() {
  _jira_validate_env || return 1

  if ! _jira_authenticate; then
    echo "Error: Jira authentication failed. Please check JIRA_TOKEN and JIRA_BASE_URL."
    return 1
  fi

  if [ $# -eq 0 ]; then
    local selection
    selection=$(_jira_menu_fzf)
    if [ -z "$selection" ]; then
      echo "No operation selected."
      return 1
    fi
    $selection
    return
  fi

  local cmd="$1"
  shift
  case "$cmd" in
    help|list)
      _jira_menu
      ;;
    describe_ticket|create_ticket|update_ticket|my_resolved_tickets|my_filed_tickets|my_open_tickets|show_epic_summary)
      $cmd "$@"
      ;;
    *)
      echo "Error: Unknown Jira command '$cmd'. Type 'jira help' to see available operations."
      return 1
      ;;
  esac
}

_jira_authenticate() {
  local response
  response=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" "${JIRA_BASE_URL}/rest/api/2/myself" 2>/dev/null) || {
    echo "Error: Authentication failed. Check JIRA_TOKEN and JIRA_BASE_URL."
    return 1
  }
  if printf '%s' "$response" | jq -e '.name' >/dev/null 2>&1; then
    return 0
  else
    echo "Error: Authentication failed. Invalid JIRA_TOKEN or inaccessible JIRA_BASE_URL."
    return 1
  fi
}

_jira_menu() {
  local items
  items=$(cat <<'EOF'
describe_ticket|Show details for a Jira ticket
create_ticket|Create a Jira ticket interactively
update_ticket|Update ticket state, fields, comments, or assignee
my_resolved_tickets|List tickets you resolved in a timeframe
my_filed_tickets|List tickets you reported in a timeframe
my_open_tickets|List your unresolved assigned tickets
show_epic_summary|List all tickets linked to an Epic
EOF
)
  printf '%s\n' "$items" | while IFS='|' read -r name desc; do
    printf '  %-22s %s\n' "$name" "$desc"
  done
}

_jira_menu_fzf() {
  local selection
  selection=$(printf '%s\n' "describe_ticket|Show details for a Jira ticket" \
    "create_ticket|Create a Jira ticket interactively" \
    "update_ticket|Update ticket state, fields, comments, or assignee" \
    "my_resolved_tickets|List tickets you resolved in a timeframe" \
    "my_filed_tickets|List tickets you reported in a timeframe" \
    "my_open_tickets|List your unresolved assigned tickets" \
    "show_epic_summary|List all tickets linked to an Epic" | \
    fzf --prompt="Jira Operation > " --height=50% --reverse --border \
      --delimiter='|' --with-nth=1,2 --preview='echo {}' )
  if [ -z "$selection" ]; then
    return 1
  fi
  printf '%s' "${selection%%|*}"
}

# ------------------------------------------------------------------------------
# Describe Jira Ticket
# Fetch and neatly format details, priority, assignee, and description for a ticket.
# Usage: describe_ticket <TICKET_KEY>
# ------------------------------------------------------------------------------
describe_ticket() {
  _jira_validate_env || return 1

  if [ -z "$1" ]; then
    echo "Usage: describe_ticket <TICKET_KEY>"
    echo "Examples:"
    echo "  describe_ticket clstr-15888"
    echo "  describe_ticket ENG-1234"
    return 1
  fi

  # Reject standalone numerical inputs without a project key
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: Please provide a full ticket key (e.g., CLSTR-$1 or ENG-$1)."
    return 1
  fi

  # Normalize issue key to uppercase
  local ISSUE="$(echo "$1" | tr '[:lower:]' '[:upper:]')"

  echo "Fetching $ISSUE..."
  local RAW_RESPONSE FIELD_METADATA_FILE FORMAT_STATUS
  RAW_RESPONSE=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE")
  FIELD_METADATA_FILE=$(mktemp "${TMPDIR:-/tmp}/jira-fields.XXXXXX") || {
    echo "Error: Could not create a temporary file for Jira field metadata."
    return 1
  }
  curl -s -o "$FIELD_METADATA_FILE" -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/field"

  if [ -z "$RAW_RESPONSE" ]; then
    rm -f "$FIELD_METADATA_FILE"

    echo "Error: Received empty response from Jira server."
    return 1
  fi

  python3 -c '
import json
import os
import sys
import urllib.error
import urllib.request

jira_token = sys.argv[2]

try:
    data = json.loads(sys.stdin.read())
    with open(sys.argv[1], encoding="utf-8") as metadata_file:
        metadata = json.load(metadata_file)
except Exception:
    print("Error: Received invalid JSON payload from server.")
    sys.exit(1)

errs = data.get("errorMessages")
if errs:
    print("Error: " + str(errs[0]))
    sys.exit(1)

fields = data.get("fields")
if not fields:
    print("Error: Ticket not found or access denied.")
    sys.exit(1)

field_names = {item.get("id"): item.get("name") for item in metadata if item.get("id")}
key = data.get("key", "N/A")
ticket_type = fields.get("issuetype", {}).get("name", "N/A") if fields.get("issuetype") else "N/A"
summary = fields.get("summary", "N/A")
status = fields.get("status", {}).get("name", "N/A") if fields.get("status") else "N/A"
priority = fields.get("priority", {}).get("name", "None") if fields.get("priority") else "None"
assignee = fields.get("assignee", {}).get("displayName", "Unassigned") if fields.get("assignee") else "Unassigned"
reporter = fields.get("reporter", {}).get("displayName", "Unknown") if fields.get("reporter") else "Unknown"
components = ", ".join(item.get("name", "") for item in fields.get("components", []) if item.get("name")) or "None"
created = fields.get("created", "N/A")
description = fields.get("description") or "No description provided."


def display_value(value):
    if value is None or value == "":
        return "None"
    if isinstance(value, list):
        values = [display_value(item) for item in value]
        return ", ".join(item for item in values if item != "None") or "None"
    if isinstance(value, dict):
        for field in ("displayName", "name", "value", "key"):
            if value.get(field) not in (None, ""):
                return str(value[field])
        return json.dumps(value, sort_keys=True)
    return str(value)


def find_field(*names):
    wanted = {name.lower() for name in names}
    for field_id, value in fields.items():
        field_name = field_names.get(field_id, field_id)
        if field_name and field_name.lower() in wanted:
            return value
    return None

optional_fields = [
    ("Affects Version(s)", ("Affects Version/s", "Affects Versions")),
    ("Fix Version(s)", ("Fix Version/s", "Fix Versions")),
    ("Integrated Version(s)", ("Integrated Version", "Integrated Version/s", "Integrated Versions", "Integrated version/s")),
    ("Verified Version(s)", ("Verified Version", "Verified Version/s", "Verified Versions", "Verified version/s")),
    ("Labels", ("Labels",)),
]

assignee_manager = find_field("Assignee Manager")
reporter_manager = find_field("Reporter Manager")
qa_contact = find_field("QA Contact")
if qa_contact is None and "customfield_10860" in fields:
    qa_contact = fields["customfield_10860"]

display_fields = [
    ("Ticket", key),
    ("Type", ticket_type),
    ("Summary", summary),
    ("Status", status),
    ("Priority", priority),
    ("Assignee", assignee),
    ("Reporter", reporter),
    ("Component(s)", components),
    ("Created", created),
]
for label, names in optional_fields:
    value = find_field(*names)
    if value is not None:
        display_fields.append((label, display_value(value)))

other_field_ids = [
    "customfield_14262",
    "customfield_13762",
]
for field_id in other_field_ids:
    if field_id in fields:
        field_name = field_names.get(field_id, field_id)
        display_fields.append((field_name, display_value(fields[field_id])))

epic_link = find_field("Epic Link")
display_fields.append(("Epic Link", display_value(epic_link)))
if isinstance(epic_link, str) and epic_link:
    try:
        request = urllib.request.Request(
            "${JIRA_BASE_URL}/rest/api/2/issue/" + epic_link + "?fields=summary",
            headers={"Authorization": "Bearer " + jira_token}
        )
        with urllib.request.urlopen(request) as epic_response:
            epic_summary = json.load(epic_response).get("fields", {}).get("summary")
        if epic_summary:
            display_fields.append(("Epic Summary", epic_summary))
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError):
        pass
display_fields.append(("QA Contact", display_value(qa_contact)))
for label, value in (("Assignee Manager", assignee_manager), ("Reporter Manager", reporter_manager)):
    if value is not None:
        display_fields.append((label, display_value(value)))

label_width = max(len(label) for label, _ in display_fields) + 2
print("================================================================================")
for label, value in display_fields:
    print(f"{label:<{label_width}}:  {value}")
print("================================================================================")
print("DESCRIPTION:\n" + str(description))
print("================================================================================")
' "$FIELD_METADATA_FILE" "$JIRA_TOKEN" <<< "$RAW_RESPONSE"
  FORMAT_STATUS=$?
  rm -f "$FIELD_METADATA_FILE"
  return $FORMAT_STATUS
}

alias show_ticket='describe_ticket'

# Search users who can be assigned on a project.
# Usage: _jira_assignable_users <query> <project_key>
# Prints TSV: username, display name, email.
_jira_assignable_users() {
  _jira_validate_env || return 1

  local query="$1"
  local project_key="$2"
  if [ ${#query} -lt 2 ] || [ -z "$project_key" ]; then
    return 0
  fi

  local encoded
  encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$query")

  local response
  response=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/user/assignable/search?project=${project_key}&username=${encoded}&maxResults=100" 2>/dev/null) || return 0

  printf '%s' "$response" | jq -r '
    if type == "array" then
      .[]?
      | select(.active != false)
      | [(.name // .key // ""), (.displayName // .name // "Unknown"), (.emailAddress // "")]
      | @tsv
    else
      empty
    end
  ' 2>/dev/null
}

# ------------------------------------------------------------------------------
# Create Ticket
# Create a new Jira issue under CLSTR or ENG with fuzzy selections.
# Usage: create_ticket [PROJECT] <PRIORITY> <TYPE> <COMPONENT> <TITLE> <DESCRIPTION> [ASSIGNEE] [PRIMARY_COMPONENT] [EPIC]
# Examples:
#   create_ticket PROJECT "Priority Name" Bug "Component" "Fix login timeout" "Investigate and fix timeout in auth flow"
#   create_ticket PROJECT "Priority Name" Task "Component" "DB failover bug" "Handle replica lag" jane.doe
#   create_ticket PROJECT "Priority Name" Story "Component" "Improve dashboard UX" "Rework filters" jane.doe "" PROJECT-1234
#   create_ticket --help
# ------------------------------------------------------------------------------
create_ticket() {
  _jira_validate_env || return 1

  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    cat <<'EOF'
Usage:
  create_ticket [PROJECT] <PRIORITY> <TYPE> <COMPONENT> <TITLE> <DESCRIPTION> [ASSIGNEE] [PRIMARY_COMPONENT] [EPIC]

Arguments:
  PROJECT      Optional. Selected from accessible Jira projects when omitted
  PRIORITY     Required. Selected from priorities allowed for the project and issue type
  TYPE         Required. Issue type (for example Task/Bug/Story/Epic)
  COMPONENT    Required. Component name
  TITLE        Required. Ticket summary
  DESCRIPTION  Required. Ticket description
  ASSIGNEE     Optional. Jira username. Defaults to current authenticated user
  PRIMARY_COMPONENT  Required for ENG. The ENG Primary Component value. Prompted interactively if omitted
  EPIC         Optional. Epic key (for example CLSTR-1234 or ENG-1234). Must be the last argument

Interactive behavior:
  - Running without arguments starts a guided interactive flow.
  - PROJECT is selected via fuzzy picker when omitted or invalid.
  - PRIORITY is selected via fuzzy picker when omitted or invalid.
  - TYPE is validated against supported issue types for the selected PROJECT.
  - If TYPE is invalid, a fuzzy picker is shown to choose from supported types.
  - COMPONENT is validated against components for the selected PROJECT.
  - If COMPONENT is invalid, a fuzzy picker is shown to choose from available components.
  - TITLE is prompted when omitted.
  - DESCRIPTION supports multiline input when omitted (finish with EOF or eof on a new line).
   - ASSIGNEE defaults to the current user; use the interactive picker to change
     the assignee to another user via a searchable dropdown, or leave unassigned.
  - For non-Epic tickets, if EPIC is not supplied, you can optionally link an Epic.
  - If linking is enabled, Epic candidates include:
      * In-progress epics assigned to you
      * In-progress epics where at least one linked issue is assigned to you
      * Results are searched across both CLSTR and ENG projects
  - Epic selection uses a fuzzy picker.
  - For ENG tickets, required fields like Primary Component, Fix Version/s,
    Impact, Regression?, and Affects Version/s are prompted automatically.

Examples:
  create_ticket PROJECT "Priority Name" Bug "Component" "Fix login timeout" "Investigate and fix timeout in auth flow"
  create_ticket PROJECT "Priority Name" Task "Component" "DB failover bug" "Handle replica lag" jane.doe
  create_ticket PROJECT "Priority Name" Story "Component" "Improve dashboard UX" "Rework filters" jane.doe "" PROJECT-1234
EOF
    return 0
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    echo "Error: fzf is required for fuzzy selection. Please install fzf and try again."
    return 1
  fi

  local PROJECT_KEY_INPUT=""
  [ -n "$1" ] && PROJECT_KEY_INPUT="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  local PROJECT_KEY=""
  local PRIORITY_INPUT=""
  local PRIORITY_ID=""
  local PRIORITY_NAME=""
  local PRIORITY_OPTIONS=""
  local ISSUE_TYPE_INPUT=""
  local COMPONENT_NAME=""
  local -a COMPONENT_NAMES=()
  local SUMMARY=""
  local DESCRIPTION=""
  local ASSIGNEE=""
  local EPIC_KEY_INPUT=""
  local ISSUE_TYPE_NAME=""
  local SELECTED_EPIC_KEY=""
  local EPIC_LINK_FIELD_ID=""
  local EXTRA_FIELDS_JSON='{}'

  echo "Fetching available projects from ${JIRA_BASE_URL}..."
  local PROJECT_ROWS
  PROJECT_ROWS=$(_jira_list_projects) || {
    echo "Error: Could not fetch projects from Jira."
    return 1
  }
  if [ -z "$PROJECT_ROWS" ]; then
    echo "Error: No accessible Jira projects were found."
    return 1
  fi

  local PROJECT_SELECTION
  PROJECT_SELECTION=$(printf '%s\n' "$PROJECT_ROWS" | fzf --prompt="Project > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=1,2)
  if [ -z "$PROJECT_SELECTION" ]; then
    echo "No project selected. Aborting."
    return 1
  fi
  PROJECT_KEY="${PROJECT_SELECTION%%$'\t'*}"
  shift $(( $# > 0 ? 1 : 0 ))

  PRIORITY_INPUT="$1"
  ISSUE_TYPE_INPUT="$2"
  COMPONENT_NAME="$3"
  SUMMARY="$4"
  DESCRIPTION="$5"
  ASSIGNEE="$6"
  local PRIMARY_COMPONENT="$7"
  EPIC_KEY_INPUT="$(echo "$8" | tr '[:lower:]' '[:upper:]')"

  # Guided mode: fill missing required values interactively.

  # Fetch current authenticated user; assignee defaults to this
  local CURRENT_USER
  CURRENT_USER=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" "${JIRA_BASE_URL}/rest/api/2/myself" | jq -r '.name // .key')

  # Assignee: defaults to current user; prompt to confirm/change
  if [ -z "$ASSIGNEE" ]; then
    ASSIGNEE="$CURRENT_USER"
  else
    local ASSIGNEE_MATCH
    ASSIGNEE_MATCH=$(printf '%s' "$ASSIGNEE" | tr '[:lower:]' '[:upper:]')
    if [[ "$ASSIGNEE_MATCH" == "NONE" || "$ASSIGNEE_MATCH" == "UNASSIGNED" ]]; then
      ASSIGNEE=""
    fi
  fi

  echo "Fetching supported issue types for $PROJECT_KEY..."
  local ISSUE_TYPES_JSON
  local PROJECT_JSON=""
  local ISSUE_TYPE_ID=""
  ISSUE_TYPES_JSON=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/issue/createmeta?projectKeys=$PROJECT_KEY&expand=projects.issuetypes")

  local ISSUE_TYPE_LIST=()
  while IFS= read -r line; do
    [ -n "$line" ] && ISSUE_TYPE_LIST+=("$line")
  done < <(printf '%s' "$ISSUE_TYPES_JSON" | jq -r '.projects[0].issuetypes[]? | select(.subtask != true) | .name' 2>/dev/null)

  if [ ${#ISSUE_TYPE_LIST[@]} -eq 0 ]; then
    PROJECT_JSON=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY")

    while IFS= read -r line; do
      [ -n "$line" ] && ISSUE_TYPE_LIST+=("$line")
    done < <(printf '%s' "$PROJECT_JSON" | jq -r '.issueTypes[]? | select(.subtask != true) | .name' 2>/dev/null)

    if [ ${#ISSUE_TYPE_LIST[@]} -eq 0 ]; then
      local CREATE_META_ERROR
      local PROJECT_ERROR
      CREATE_META_ERROR=$(printf '%s' "$ISSUE_TYPES_JSON" | jq -r '.errorMessages[]? // empty' 2>/dev/null | paste -sd '; ' -)
      PROJECT_ERROR=$(printf '%s' "$PROJECT_JSON" | jq -r '.errorMessages[]? // empty' 2>/dev/null | paste -sd '; ' -)

      echo "Error: Could not fetch supported issue types for $PROJECT_KEY."
      if [ -n "$CREATE_META_ERROR" ]; then
        echo "createmeta error: $CREATE_META_ERROR"
      fi
      if [ -n "$PROJECT_ERROR" ]; then
        echo "project API error: $PROJECT_ERROR"
      fi
      echo "Check JIRA_TOKEN validity and Jira project permissions for $PROJECT_KEY."
      return 1
    fi
  fi

  ISSUE_TYPE_NAME=$(printf '%s\n' "${ISSUE_TYPE_LIST[@]}" | awk -v input="$ISSUE_TYPE_INPUT" 'tolower($0) == tolower(input) { print; exit }')
  if [ -z "$ISSUE_TYPE_NAME" ]; then
    if [ -n "$ISSUE_TYPE_INPUT" ]; then
      echo "Provided type '$ISSUE_TYPE_INPUT' is not supported. Pick one from the fuzzy list."
    fi
    ISSUE_TYPE_NAME=$(printf '%s\n' "${ISSUE_TYPE_LIST[@]}" | fzf --prompt="Ticket Type > " --height=40% --reverse --border)
    if [ -z "$ISSUE_TYPE_NAME" ]; then
      echo "No ticket type selected. Aborting."
      return 1
    fi
  fi

  ISSUE_TYPE_ID=$(printf '%s' "$ISSUE_TYPES_JSON" | jq -r --arg issue_type_name "$ISSUE_TYPE_NAME" '
    .projects[0].issuetypes[]?
    | select((.name // "" | ascii_downcase) == ($issue_type_name | ascii_downcase))
    | .id
  ' 2>/dev/null | head -n 1)

  if [ -z "$ISSUE_TYPE_ID" ]; then
    if [ -z "$PROJECT_JSON" ]; then
      PROJECT_JSON=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
        "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY")
    fi
    ISSUE_TYPE_ID=$(printf '%s' "$PROJECT_JSON" | jq -r --arg issue_type_name "$ISSUE_TYPE_NAME" '
      .issueTypes[]?
      | select((.name // "" | ascii_downcase) == ($issue_type_name | ascii_downcase))
      | .id
    ' 2>/dev/null | head -n 1)
  fi

  if [ -z "$ISSUE_TYPE_ID" ] || [ "$ISSUE_TYPE_ID" = "null" ]; then
    echo "Error: Could not resolve the Jira issue type ID for '$ISSUE_TYPE_NAME'."
    return 1
  fi

  echo "Fetching priorities for $PROJECT_KEY / $ISSUE_TYPE_NAME..."
  PRIORITY_OPTIONS=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/issue/createmeta/$PROJECT_KEY/issuetypes/$ISSUE_TYPE_ID" \
    | jq -r '.values[]? | select(.fieldId == "priority") | .allowedValues[]? | [(.id // ""), (.name // "")] | @tsv' 2>/dev/null) || {
    echo "Error: Could not fetch priorities for $PROJECT_KEY / $ISSUE_TYPE_NAME."
    return 1
  }
  if [ -z "$PRIORITY_OPTIONS" ]; then
    echo "Error: No priorities are allowed for $PROJECT_KEY / $ISSUE_TYPE_NAME."
    return 1
  fi

  local PRIORITY_SELECTION
  if [ -n "$PRIORITY_INPUT" ]; then
    PRIORITY_SELECTION=$(printf '%s\n' "$PRIORITY_OPTIONS" | awk -F '\t' -v input="$PRIORITY_INPUT" '
      tolower($1) == tolower(input) || tolower($2) == tolower(input) { print; exit }
    ')
  fi
  if [ -z "$PRIORITY_SELECTION" ]; then
    if [ -n "$PRIORITY_INPUT" ]; then
      echo "Provided priority '$PRIORITY_INPUT' is not allowed for $PROJECT_KEY / $ISSUE_TYPE_NAME. Pick one from the fuzzy list."
    fi
    PRIORITY_SELECTION=$(printf '%s\n' "$PRIORITY_OPTIONS" | fzf --prompt="Priority > " --height=40% --reverse --border --delimiter=$'\t' --with-nth=2)
    if [ -z "$PRIORITY_SELECTION" ]; then
      echo "No priority selected. Aborting."
      return 1
    fi
  fi
  PRIORITY_ID="${PRIORITY_SELECTION%%$'\t'*}"
  PRIORITY_NAME="${PRIORITY_SELECTION#*$'\t'}"

  echo "Fetching available components for $PROJECT_KEY..."
  local COMPONENTS_JSON COMPONENT
  COMPONENTS_JSON=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY/components")

  local COMPONENT_LIST=()
  while IFS= read -r line; do
    [ -n "$line" ] && COMPONENT_LIST+=("$line")
  done < <(printf '%s' "$COMPONENTS_JSON" | jq -r '.[].name' 2>/dev/null)

  if [ ${#COMPONENT_LIST[@]} -eq 0 ]; then
    echo "Error: No components found for project $PROJECT_KEY."
    return 1
  fi

  if [ -n "$COMPONENT_NAME" ]; then
    local MATCHED_COMPONENT
    MATCHED_COMPONENT=$(printf '%s\n' "${COMPONENT_LIST[@]}" | awk -v input="$COMPONENT_NAME" 'tolower($0) == tolower(input) { print; exit }')
    if [ -n "$MATCHED_COMPONENT" ]; then
      COMPONENT_NAMES+=("$MATCHED_COMPONENT")
    else
      echo "Provided component '$COMPONENT_NAME' not found. Pick one from the fuzzy list."
    fi
  fi

  while true; do
    local AVAILABLE_COMPONENTS=""
    for COMPONENT in "${COMPONENT_LIST[@]}"; do
      if (( ${COMPONENT_NAMES[(Ie)$COMPONENT]} == 0 )); then
        AVAILABLE_COMPONENTS+="$COMPONENT\n"
      fi
    done
    if [ -z "$AVAILABLE_COMPONENTS" ]; then
      break
    fi

    if [ ${#COMPONENT_NAMES[@]} -gt 0 ]; then
      local ADD_COMPONENT_CHOICE
      ADD_COMPONENT_CHOICE=$(printf 'No\nYes\n' | fzf --prompt="Add another component? > " --height=40% --reverse --border)
      [ "$ADD_COMPONENT_CHOICE" != "Yes" ] && break
    fi

    local SELECTED_COMPONENT
    SELECTED_COMPONENT=$(printf '%b' "$AVAILABLE_COMPONENTS" | fzf --prompt="Component > " --height=50% --reverse --border)
    if [ -z "$SELECTED_COMPONENT" ]; then
      echo "No component selected. Aborting."
      return 1
    fi
    COMPONENT_NAMES+=("$SELECTED_COMPONENT")
  done

  if [ ${#COMPONENT_NAMES[@]} -eq 0 ]; then
    echo "At least one component is required. Aborting."
    return 1
  fi
  COMPONENT_NAME="${(j:, :)COMPONENT_NAMES}"

  if [ -z "$SUMMARY" ]; then
    echo -n "Title > "
    read -r SUMMARY
    if [ -z "$SUMMARY" ]; then
      echo "Title is required. Aborting."
      return 1
    fi
  fi

  if [ -z "$DESCRIPTION" ]; then
    local -a DESCRIPTION_LINES=()
    local DESCRIPTION_LINE=""
    echo "Description > (multiline; type EOF or eof on a new line to finish)"
    while true; do
      IFS= read -r DESCRIPTION_LINE
      if [[ "${DESCRIPTION_LINE:l}" == "eof" ]]; then
        break
      fi
      DESCRIPTION_LINES+=("$DESCRIPTION_LINE")
    done
    DESCRIPTION="${(j:\n:)DESCRIPTION_LINES}"
    if [ -z "$DESCRIPTION" ]; then
      echo "Description is required. Aborting."
      return 1
    fi
  fi

  if [ "$PROJECT_KEY" = "ENG" ] && [ -z "$PRIMARY_COMPONENT" ]; then
    if [ ${#COMPONENT_LIST[@]} -gt 0 ]; then
      PRIMARY_COMPONENT=$(printf '%s\n' "${COMPONENT_LIST[@]}" | fzf --prompt="Primary Component > " --height=40% --reverse --border)
    else
      echo -n "Primary Component (ENG required) > "
      read -r PRIMARY_COMPONENT
    fi
    if [ -z "$PRIMARY_COMPONENT" ]; then
      echo "Primary Component is required for ENG tickets. Aborting."
      return 1
    fi
  fi

  # Assignee prompt: show dropdown with current default, allow picking another user or unassigning
  local ASSIGNEE_CHOICE
  if [ -z "$ASSIGNEE" ]; then
    ASSIGNEE_CHOICE=$(printf "Set Assignee\nUnassign\n" | fzf --prompt="Assignee > " --height=40% --reverse --border)
  else
    ASSIGNEE_CHOICE=$(printf "Keep [$ASSIGNEE]\nChange Assignee\nUnassign\n" | fzf --prompt="Assignee > " --height=40% --reverse --border)
  fi
  if [ "$ASSIGNEE_CHOICE" = "Change Assignee" ] || [ "$ASSIGNEE_CHOICE" = "Set Assignee" ]; then
    local _assignee_query _assignee_rows _selected _picked
    echo -n "Assignee search > "
    read -r _assignee_query
    if [ ${#_assignee_query} -lt 2 ]; then
      echo "Type at least 2 characters to search assignees."
    else
      echo "Searching assignees in ${PROJECT_KEY}..."
      _assignee_rows=$(_jira_assignable_users "$_assignee_query" "$PROJECT_KEY")
      if [ -z "$_assignee_rows" ]; then
        echo "No assignable users found for '${_assignee_query}'."
      else
        _selected=$(printf '%s\n' "$_assignee_rows" | fzf --prompt="Assignee > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2,3)
        _picked=$(printf '%s' "$_selected" | cut -f1)
        if [ -n "$_picked" ]; then
          ASSIGNEE="$_picked"
        fi
      fi
    fi
  elif [ "$ASSIGNEE_CHOICE" = "Unassign" ]; then
    ASSIGNEE=""
  fi

  if [[ "${ISSUE_TYPE_NAME:l}" != "epic" && -n "$EPIC_KEY_INPUT" ]]; then
    SELECTED_EPIC_KEY="$EPIC_KEY_INPUT"
  fi

  if [[ "${ISSUE_TYPE_NAME:l}" != "epic" && -z "$SELECTED_EPIC_KEY" ]]; then
    local LINK_EPIC_CHOICE
    LINK_EPIC_CHOICE=$(printf "No\nYes\n" | fzf --prompt="Link to an in-progress epic? > " --height=40% --reverse --border)

    if [ "$LINK_EPIC_CHOICE" = "Yes" ]; then
      echo "Fetching Epic Link field metadata..."
      EPIC_LINK_FIELD_ID=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
        "${JIRA_BASE_URL}/rest/api/2/field" \
        | jq -r '.[] | select(.name == "Epic Link") | .id' | head -n 1)

      if [ -z "$EPIC_LINK_FIELD_ID" ] || [ "$EPIC_LINK_FIELD_ID" = "null" ]; then
        echo "Could not locate the 'Epic Link' field. Skipping epic linking."
      else
        local EPIC_LINK_FIELD_NUM="${EPIC_LINK_FIELD_ID#customfield_}"
        local ASSIGNED_EPICS_JQL="project in (CLSTR, ENG) AND issuetype = Epic AND statusCategory != Done AND assignee = currentUser() ORDER BY updated DESC"
        local ASSIGNED_EPICS_ENCODED
        ASSIGNED_EPICS_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$ASSIGNED_EPICS_JQL")

        local ASSIGNED_EPICS_RESPONSE
        ASSIGNED_EPICS_RESPONSE=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
          "${JIRA_BASE_URL}/rest/api/2/search?jql=${ASSIGNED_EPICS_ENCODED}&maxResults=500&fields=key,summary,status,assignee")

        if printf '%s' "$ASSIGNED_EPICS_RESPONSE" | jq -e '.errorMessages' >/dev/null 2>&1; then
          local _epic_err
          _epic_err=$(printf '%s' "$ASSIGNED_EPICS_RESPONSE" | jq -r '.errorMessages[]' 2>/dev/null | head -n 1)
          echo "Warning: Epic search query returned error: $_epic_err"
          ASSIGNED_EPICS_RESPONSE='{"issues":[]}'
        fi

        local MY_ISSUES_WITH_EPIC_JQL="project in (CLSTR, ENG) AND assignee = currentUser() AND statusCategory != Done AND cf[${EPIC_LINK_FIELD_NUM}] IS NOT EMPTY ORDER BY updated DESC"
        local MY_ISSUES_WITH_EPIC_ENCODED
        MY_ISSUES_WITH_EPIC_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$MY_ISSUES_WITH_EPIC_JQL")

        local MY_ISSUES_WITH_EPIC_RESPONSE
        MY_ISSUES_WITH_EPIC_RESPONSE=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
          "${JIRA_BASE_URL}/rest/api/2/search?jql=${MY_ISSUES_WITH_EPIC_ENCODED}&maxResults=500&fields=key,summary,${EPIC_LINK_FIELD_ID}")

        if printf '%s' "$MY_ISSUES_WITH_EPIC_RESPONSE" | jq -e '.errorMessages' >/dev/null 2>&1; then
          local _epic_err2
          _epic_err2=$(printf '%s' "$MY_ISSUES_WITH_EPIC_RESPONSE" | jq -r '.errorMessages[]' 2>/dev/null | head -n 1)
          echo "Warning: Epic-related issues query returned error: $_epic_err2"
          MY_ISSUES_WITH_EPIC_RESPONSE='{"issues":[]}'
        fi

        local RELATED_EPIC_KEYS=()
        while IFS= read -r key; do
          [ -n "$key" ] && RELATED_EPIC_KEYS+=("$key")
        done < <(printf '%s' "$MY_ISSUES_WITH_EPIC_RESPONSE" | jq -r --arg epic_field "$EPIC_LINK_FIELD_ID" '.issues[]?.fields[$epic_field] // empty' 2>/dev/null | sort -u)

        local RELATED_EPICS_RESPONSE='{"issues":[]}'
        if [ ${#RELATED_EPIC_KEYS[@]} -gt 0 ]; then
          local KEYS_CSV=""
          local key
          for key in "${RELATED_EPIC_KEYS[@]}"; do
            KEYS_CSV="${KEYS_CSV}'${key}',"
          done
          KEYS_CSV="${KEYS_CSV%,}"

          local RELATED_EPICS_JQL="project in (CLSTR, ENG) AND issuetype = Epic AND statusCategory != Done AND key IN (${KEYS_CSV}) ORDER BY updated DESC"
          local RELATED_EPICS_ENCODED
          RELATED_EPICS_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$RELATED_EPICS_JQL")

          RELATED_EPICS_RESPONSE=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
            "${JIRA_BASE_URL}/rest/api/2/search?jql=${RELATED_EPICS_ENCODED}&maxResults=500&fields=key,summary,status,assignee")

          if printf '%s' "$RELATED_EPICS_RESPONSE" | jq -e '.errorMessages' >/dev/null 2>&1; then
            local _epic_err3
            _epic_err3=$(printf '%s' "$RELATED_EPICS_RESPONSE" | jq -r '.errorMessages[]' 2>/dev/null | head -n 1)
            echo "Warning: Related epics query returned error: $_epic_err3"
            RELATED_EPICS_RESPONSE='{"issues":[]}'
          fi
        fi

        local MERGED_EPIC_RESPONSES
        MERGED_EPIC_RESPONSES=$(jq -s '{issues: [.[0].issues[]?, .[1].issues[]?]}' \
          <(printf '%s' "$ASSIGNED_EPICS_RESPONSE") \
          <(printf '%s' "$RELATED_EPICS_RESPONSE") 2>/dev/null)

        if [ -z "$MERGED_EPIC_RESPONSES" ] || ! printf '%s' "$MERGED_EPIC_RESPONSES" | jq -e '.issues | type == "array"' >/dev/null 2>&1; then
          echo "Warning: Failed to merge epic responses. Using assigned epics only."
          MERGED_EPIC_RESPONSES="$ASSIGNED_EPICS_RESPONSE"
        fi

        local EPIC_PICK_LIST_RAW
        EPIC_PICK_LIST_RAW=$(printf '%s' "$MERGED_EPIC_RESPONSES" | jq -r '
          [(.issues[]? | {
              key: .key,
              summary: (.fields.summary // ""),
              assignee: (.fields.assignee.displayName // "Unassigned")
            })] as $items
          | reduce $items[] as $item ({}; .[$item.key] = $item)
          | to_entries[]
          | "\(.value.key)\t\(.value.summary)\t\(.value.assignee)"
        ' 2>/dev/null | sort)

        if [ -z "$EPIC_PICK_LIST_RAW" ]; then
          echo "No eligible in-progress epics found for linking."
        else
          local SELECTED_EPIC_LINE
          SELECTED_EPIC_LINE=$(printf '%s\n' "$EPIC_PICK_LIST_RAW" | fzf --prompt="Epic > " --height=50% --reverse --border --with-nth=2,3 --delimiter=$'\t')
          if [ -n "$SELECTED_EPIC_LINE" ]; then
            SELECTED_EPIC_KEY=$(printf '%s' "$SELECTED_EPIC_LINE" | cut -f1)
          fi
        fi
      fi
    fi
  fi

  if [[ -n "$SELECTED_EPIC_KEY" && -z "$EPIC_LINK_FIELD_ID" ]]; then
    EPIC_LINK_FIELD_ID=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/field" \
      | jq -r '.[] | select(.name == "Epic Link") | .id' | head -n 1)
    if [ -z "$EPIC_LINK_FIELD_ID" ] || [ "$EPIC_LINK_FIELD_ID" = "null" ]; then
      echo "Could not locate the 'Epic Link' field. Skipping epic linking."
      SELECTED_EPIC_KEY=""
    fi
  fi

  if [ "$PROJECT_KEY" = "ENG" ]; then
    EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg val "$PRIMARY_COMPONENT" '. + {"customfield_15160": {"value": $val}}')
  fi

  local FIX_VERSION_OPTIONS FIX_VERSION_SELECTION FIX_VERSION_ID FIX_VERSION_NAME
  local -a CREATE_FIX_VERSION_IDS CREATE_FIX_VERSION_NAMES
  FIX_VERSION_OPTIONS=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY/versions" \
    | jq -r '.[]? | select(.archived != true) | [(.id // ""), (.name // "Unknown")] | @tsv' 2>/dev/null)
  if [ -z "$FIX_VERSION_OPTIONS" ]; then
    echo "No selectable Fix Version/s found for $PROJECT_KEY."
    return 1
  fi

  CREATE_FIX_VERSION_IDS=()
  CREATE_FIX_VERSION_NAMES=()
  while true; do
    local CREATE_AVAILABLE_VERSIONS=""
    while IFS=$'\t' read -r FIX_VERSION_ID FIX_VERSION_NAME; do
      [ -z "$FIX_VERSION_ID" ] && continue
      if (( ${CREATE_FIX_VERSION_IDS[(Ie)$FIX_VERSION_ID]} == 0 )); then
        CREATE_AVAILABLE_VERSIONS+="${FIX_VERSION_ID}\t${FIX_VERSION_NAME}\n"
      fi
    done <<< "$FIX_VERSION_OPTIONS"

    if [ -z "$CREATE_AVAILABLE_VERSIONS" ]; then
      echo "All available Fix Version/s have been selected."
      break
    fi

    FIX_VERSION_SELECTION=$(printf '%b' "$CREATE_AVAILABLE_VERSIONS" | fzf --prompt="Fix Version/s > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2)
    if [ -z "$FIX_VERSION_SELECTION" ]; then
      echo "Fix Version/s selection is required. Aborting."
      return 1
    fi

    FIX_VERSION_ID="${FIX_VERSION_SELECTION%%$'\t'*}"
    FIX_VERSION_NAME="${FIX_VERSION_SELECTION#*$'\t'}"
    CREATE_FIX_VERSION_IDS+=("$FIX_VERSION_ID")
    CREATE_FIX_VERSION_NAMES+=("$FIX_VERSION_NAME")

    local ADD_CREATE_FIX_VERSION
    ADD_CREATE_FIX_VERSION=$(printf 'No\nYes\n' | fzf --prompt="Add another Fix Version/s? > " --height=40% --reverse --border)
    [ "$ADD_CREATE_FIX_VERSION" != "Yes" ] && break
  done

  local CREATE_FIX_VERSIONS_PAYLOAD='[]'
  local CREATE_FIX_VERSION_ID
  for CREATE_FIX_VERSION_ID in "${CREATE_FIX_VERSION_IDS[@]}"; do
    CREATE_FIX_VERSIONS_PAYLOAD=$(printf '%s' "$CREATE_FIX_VERSIONS_PAYLOAD" | jq --arg id "$CREATE_FIX_VERSION_ID" '. + [{id: $id}]')
  done
  EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --argjson fix_versions "$CREATE_FIX_VERSIONS_PAYLOAD" '. + {fixVersions: $fix_versions}')

  echo "Fetching required fields for $ISSUE_TYPE_NAME in $PROJECT_KEY..."

  local ISSUETYPE_FIELDS_JSON=""

  if [ -n "$ISSUE_TYPE_ID" ]; then
    ISSUETYPE_FIELDS_JSON=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/issue/createmeta/$PROJECT_KEY/issuetypes/$ISSUE_TYPE_ID" 2>/dev/null)

    if ! printf '%s' "$ISSUETYPE_FIELDS_JSON" | jq -e '.values' >/dev/null 2>&1; then
      ISSUETYPE_FIELDS_JSON=""
    fi
  fi

  if [ -z "$ISSUETYPE_FIELDS_JSON" ]; then
    local ISSUETYPE_CREATE_META_JSON
    ISSUETYPE_CREATE_META_JSON=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/issue/createmeta?projectKeys=$PROJECT_KEY&expand=projects.issuetypes.fields")

    if printf '%s' "$ISSUETYPE_CREATE_META_JSON" | jq -e '.projects[0].issuetypes' >/dev/null 2>&1; then
      ISSUETYPE_FIELDS_JSON=$(printf '%s' "$ISSUETYPE_CREATE_META_JSON" | jq -c \
        --arg issue_type_id "$ISSUE_TYPE_ID" \
        --arg issue_type_name "$ISSUE_TYPE_NAME" '
        {values: (
          .projects[0].issuetypes[]?
          | select(
              if ($issue_type_id | length) > 0
              then .id == $issue_type_id
              else ((.name // "" | ascii_downcase) == ($issue_type_name | ascii_downcase))
              end
            )
          | [.fields | to_entries[] | {fieldId: .key, required: .value.required, name: .value.name, schema: .value.schema, allowedValues: .value.allowedValues}]
        )}' 2>/dev/null | head -n 1)
    fi
  fi

  _field_helper() {
    local fid="$1" json="$2" attr="$3"
    printf '%s' "$json" | jq -r --arg fid "$fid" --arg attr "$attr" '
      (.values[]? | select(.fieldId == $fid))
      | if $attr == "required" then (.required // false | tostring)
        elif $attr == "name" then (.name // $fid)
        elif $attr == "schema_type" then (.schema.type // "")
        elif $attr == "schema_items" then (.schema.items // "")
        elif $attr == "options" then (
          .allowedValues[]?
          | [(.id // ""), (.name // .value // .key // "Unknown")]
          | @tsv
        )
        else ""
        end
    ' 2>/dev/null
  }

  local REQUIRED_FIELD_IDS
  if [ -n "$ISSUETYPE_FIELDS_JSON" ]; then
    REQUIRED_FIELD_IDS=$(printf '%s' "$ISSUETYPE_FIELDS_JSON" | jq -r '
      .values[]?
      | select(.required == true)
      | .fieldId
      | select(IN(.; "project", "summary", "description", "priority", "assignee", "components", "issuetype") | not)
    ' 2>/dev/null)
  fi

  local FIELD_ID FIELD_LABEL FIELD_TYPE FIELD_ITEMS
  local FIELD_OPTIONS SELECTED_OPTION SELECTED_ID SELECTED_VALUE MANUAL_VALUE

  for FIELD_ID in ${(f)REQUIRED_FIELD_IDS}; do
    [ -z "$FIELD_ID" ] && continue

    if [ "$FIELD_ID" = "reporter" ]; then
      if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" = "null" ]; then
        echo "Could not resolve the current user for Reporter. Aborting."
        return 1
      fi
      EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg val "$CURRENT_USER" '. + {reporter: {"name": $val}}')
      continue
    fi

    printf '%s' "$EXTRA_FIELDS_JSON" | jq -e --arg fid "$FIELD_ID" 'has($fid)' >/dev/null 2>&1 && continue

    FIELD_LABEL=$(_field_helper "$FIELD_ID" "$ISSUETYPE_FIELDS_JSON" "name")
    FIELD_TYPE=$(_field_helper "$FIELD_ID" "$ISSUETYPE_FIELDS_JSON" "schema_type")
    FIELD_ITEMS=$(_field_helper "$FIELD_ID" "$ISSUETYPE_FIELDS_JSON" "schema_items")
    [ "$FIELD_ITEMS" = "$FIELD_TYPE" ] && FIELD_ITEMS=""
    FIELD_OPTIONS=$(_field_helper "$FIELD_ID" "$ISSUETYPE_FIELDS_JSON" "options")

    if [ -z "$FIELD_OPTIONS" ]; then
      if [[ "$FIELD_ID" = "versions" || "$FIELD_ID" = "fixVersions" ]]; then
        FIELD_OPTIONS=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
          "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY/versions" \
          | jq -r '.[]? | select(.archived != true) | [(.id // ""), (.name // "Unknown")] | @tsv' 2>/dev/null)
      elif [[ "$FIELD_TYPE" = "user" || "$FIELD_ITEMS" = "user" ]]; then
        local _user_field_name="$FIELD_ID"
        if [[ "$FIELD_ID" = customfield_* ]]; then
          _user_field_name="cf[${FIELD_ID#customfield_}]"
        fi
        local _user_field_encoded
        _user_field_encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$_user_field_name")
        local _user_suggest_json
        _user_suggest_json=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
          "${JIRA_BASE_URL}/rest/api/2/jql/autocompletedata/suggestions?fieldName=${_user_field_encoded}&fieldValue=" 2>/dev/null)
        FIELD_OPTIONS=$(printf '%s' "$_user_suggest_json" | jq -r '.results[]? | [(.accountId // .name // ""), (.displayName // .name // "Unknown")] | @tsv' 2>/dev/null)
      elif [[ "$FIELD_ID" = customfield_* ]]; then
        local _cf_num="${FIELD_ID#customfield_}"
        local _cf_suggest_json
        _cf_suggest_json=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
          "${JIRA_BASE_URL}/rest/api/2/jql/autocompletedata/suggestions?fieldName=cf%5B${_cf_num}%5D&fieldValue=" 2>/dev/null)
        FIELD_OPTIONS=$(printf '%s' "$_cf_suggest_json" | jq -r '
          .results[]? | [(""), (.displayName // .value // "Unknown")] | @tsv
        ' 2>/dev/null)
      fi
    fi

    if [ -n "$FIELD_OPTIONS" ]; then
      SELECTED_OPTION=$(printf '%s\n' "$FIELD_OPTIONS" | fzf --prompt="${FIELD_LABEL} > " --height=50% --reverse --border --with-nth=2)
      if [ -z "$SELECTED_OPTION" ]; then
        echo "No value selected for '${FIELD_LABEL}'. Aborting."
        return 1
      fi

      SELECTED_ID="${SELECTED_OPTION%%$'\t'*}"
      SELECTED_VALUE="${SELECTED_OPTION#*$'\t'}"

      if [[ "$FIELD_TYPE" = "user" || "$FIELD_ITEMS" = "user" ]]; then
        local _user_name="$SELECTED_ID"
        [ -z "$_user_name" ] && _user_name="$SELECTED_VALUE"
        if [ "$FIELD_TYPE" = "array" ]; then
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$_user_name" '. + {($fid): [{"name": $val}]}')
        else
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$_user_name" '. + {($fid): {"name": $val}}')
        fi
      elif [[ "$FIELD_ID" = customfield_* && "$FIELD_TYPE" = "string" ]]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): $val}')
      elif [[ "$FIELD_ID" = customfield_* && "$FIELD_TYPE" != "array" ]]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): {"value": $val}}')
      elif [[ "$FIELD_ID" = customfield_* && "$FIELD_TYPE" = "array" ]]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): [{"value": $val}]}')
      elif [ "$FIELD_TYPE" = "array" ]; then
        if [[ "$FIELD_ITEMS" = "option" ]]; then
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): [{"name": $val}]}')
        elif [ -n "$SELECTED_ID" ]; then
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_ID" '. + {($fid): [{"id": $val}]}')
        elif [[ "$FIELD_ITEMS" = "version" || "$FIELD_ITEMS" = "component" ]]; then
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): [{"name": $val}]}')
        else
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): [$val]}')
        fi
      elif [ "$FIELD_TYPE" = "option" ]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): {"name": $val}}')
      elif [[ "$FIELD_TYPE" = "version" || "$FIELD_TYPE" = "component" ]]; then
        if [ -n "$SELECTED_ID" ]; then
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_ID" '. + {($fid): {"id": $val}}')
        else
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): {"name": $val}}')
        fi
      else
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$SELECTED_VALUE" '. + {($fid): $val}')
      fi
    else
      echo -n "${FIELD_LABEL} > "
      read -r MANUAL_VALUE
      if [ -z "$MANUAL_VALUE" ]; then
        echo "Value required for '${FIELD_LABEL}'. Aborting."
        return 1
      fi

      if [[ "$FIELD_TYPE" = "user" || "$FIELD_ITEMS" = "user" ]]; then
        if [ "$FIELD_TYPE" = "array" ]; then
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): [{"name": $val}]}')
        else
          EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): {"name": $val}}')
        fi
      elif [[ "$FIELD_ID" = customfield_* && "$FIELD_TYPE" = "string" ]]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): $val}')
      elif [[ "$FIELD_ID" = customfield_* ]]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): {"value": $val}}')
      elif [ "$FIELD_TYPE" = "array" ]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): [{"name": $val}]}')
      elif [ "$FIELD_TYPE" = "option" ]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): {"name": $val}}')
      elif [[ "$FIELD_TYPE" = "version" || "$FIELD_TYPE" = "component" ]]; then
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): {"name": $val}}')
      else
        EXTRA_FIELDS_JSON=$(printf '%s' "$EXTRA_FIELDS_JSON" | jq --arg fid "$FIELD_ID" --arg val "$MANUAL_VALUE" '. + {($fid): $val}')
      fi
    fi
  done

  echo "================================================================================"
  echo "Review ticket details"
  echo "================================================================================"
   echo "Project:      $PROJECT_KEY"
   echo "Priority:     $PRIORITY_INPUT ($PRIORITY_NAME)"
  echo "Type:         $ISSUE_TYPE_NAME"
  echo "Component:    $COMPONENT_NAME"
  echo "Assignee:     $ASSIGNEE"
  echo "Reporter:     $CURRENT_USER"
  if [ "$PROJECT_KEY" = "ENG" ]; then
    echo "Primary Comp: $PRIMARY_COMPONENT"
  fi
  if [ -n "$SELECTED_EPIC_KEY" ]; then
    echo "Epic Link:    $SELECTED_EPIC_KEY"
  else
    echo "Epic Link:    (none)"
  fi
  echo "Title:        $SUMMARY"
  echo "Description:"
  printf '%s\n' "$DESCRIPTION"
  if [ "$PROJECT_KEY" = "ENG" ] && [ "$EXTRA_FIELDS_JSON" != "{}" ]; then
    echo "--------------------------------------------------------------------------------"
    echo "ENG Required Fields:"
    printf '%s' "$EXTRA_FIELDS_JSON" | jq .
  fi
  echo "--------------------------------------------------------------------------------"
   echo "Full Payload Preview:"
   jq -n \
     --arg project "$PROJECT_KEY" \
     --arg reporter "$REPORTER" \
     --arg summary "$SUMMARY" \
     --arg description "$DESCRIPTION" \
     --arg priority_id "$PRIORITY_ID" \
     --arg assignee "$ASSIGNEE" \
       --argjson components "$(printf '%s\n' "${COMPONENT_NAMES[@]}" | jq -R . | jq -s .)" \
       --arg issue_type "$ISSUE_TYPE_NAME" \
      --argjson extra_fields "$EXTRA_FIELDS_JSON" \
      --arg epic_field "$EPIC_LINK_FIELD_ID" \
      --arg epic_key "$SELECTED_EPIC_KEY" '
      {
        fields: {
          project: { key: $project },
          summary: $summary,
          description: $description,
          priority: { id: $priority_id },
          assignee: { name: $assignee },
          components: ($components | map({name: .})),
          issuetype: { name: $issue_type }
        }
      }
      | .fields += $extra_fields
      | if (($epic_key | length) > 0 and ($epic_field | length) > 0)
        then .fields += { ($epic_field): $epic_key }
        else .
        end
    '
   echo "================================================================================"

   local CREATE_CONFIRMATION
  CREATE_CONFIRMATION=$(printf "Create ticket\nCancel\n" | fzf --prompt="Confirm > " --height=40% --reverse --border)
  if [ "$CREATE_CONFIRMATION" != "Create ticket" ]; then
    echo "Ticket creation cancelled."
    return 1
  fi

  echo -e "\nCreating $ISSUE_TYPE_NAME ticket: $PRIORITY_INPUT ($PRIORITY_NAME) in $PROJECT_KEY (Component: $COMPONENT_NAME) assigned to $ASSIGNEE..."

    local PAYLOAD
    PAYLOAD=$(jq -n \
      --arg project "$PROJECT_KEY" \
      --arg summary "$SUMMARY" \
      --arg description "$DESCRIPTION" \
      --arg priority_id "$PRIORITY_ID" \
      --arg assignee "$ASSIGNEE" \
      --argjson components "$(printf '%s\n' "${COMPONENT_NAMES[@]}" | jq -R . | jq -s .)" \
      --arg issue_type "$ISSUE_TYPE_NAME" \
      --argjson extra_fields "$EXTRA_FIELDS_JSON" \
      --arg epic_field "$EPIC_LINK_FIELD_ID" \
      --arg epic_key "$SELECTED_EPIC_KEY" '
      {
        fields: {
          project: { key: $project },
          summary: $summary,
          description: $description,
          priority: { id: $priority_id },
          assignee: { name: $assignee },
          components: ($components | map({name: .})),
          issuetype: { name: $issue_type }
        }
      }
      | .fields += $extra_fields
      | if (($epic_key | length) > 0 and ($epic_field | length) > 0)
        then .fields += { ($epic_field): $epic_key }
        else .
        end
    ')

  # Post issue payload to Jira REST API
  local RESPONSE
  RESPONSE=$(curl -s --request POST \
    --url "${JIRA_BASE_URL}/rest/api/2/issue" \
    --header "Authorization: Bearer $JIRA_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$PAYLOAD")

  local KEY
  KEY=$(printf '%s' "$RESPONSE" | jq -r '.key // empty' 2>/dev/null)

  if [ -n "$KEY" ]; then
    echo "Successfully created ticket: ${JIRA_BASE_URL}/browse/$KEY"
    if [ -n "$SELECTED_EPIC_KEY" ]; then
      echo "Linked to epic: $SELECTED_EPIC_KEY"
    fi
  else
    echo "Failed to create ticket. Error details:"
    printf '%s' "$RESPONSE" | jq .
  fi
}

update_ticket() {
  _jira_validate_env || return 1
  emulate -L zsh

  if [ "$#" -ne 1 ]; then
    echo "Usage: update_ticket <TICKET_KEY>"
    echo "Examples:"
    echo "  update_ticket clstr-15888"
    echo "  update_ticket ENG-1234"
    return 1
  fi

  local ISSUE_INPUT
  ISSUE_INPUT=$(printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:lower:]' '[:upper:]')
  if [[ ! "$ISSUE_INPUT" =~ '^[A-Z][A-Z0-9_]*-[0-9]+$' ]]; then
    echo "Error: Ticket key must match a Jira issue key such as PROJECT-1234."
    return 1
  fi

  if ! command -v fzf >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "Error: update_ticket requires both fzf and jq."
    return 1
  fi

  local ISSUE_RESPONSE
  echo "Fetching $ISSUE_INPUT..."
  ISSUE_RESPONSE=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT?fields=summary,status,fixVersions,labels" 2>/dev/null) || {
    echo "Error: Could not fetch $ISSUE_INPUT."
    return 1
  }

  local SUMMARY CURRENT_STATUS
  SUMMARY=$(printf '%s' "$ISSUE_RESPONSE" | jq -r '.fields.summary // empty' 2>/dev/null)
  CURRENT_STATUS=$(printf '%s' "$ISSUE_RESPONSE" | jq -r '.fields.status.name // empty' 2>/dev/null)
  if [ -z "$SUMMARY" ] || [ -z "$CURRENT_STATUS" ]; then
    echo "Error: Ticket not found or access denied."
    printf '%s' "$ISSUE_RESPONSE" | jq -r '.errorMessages[]? // empty' 2>/dev/null
    return 1
  fi

  echo "Ticket: $ISSUE_INPUT — $SUMMARY"
  echo "Current status: $CURRENT_STATUS"

  local OPERATION
  OPERATION=$(printf 'State\nAdd comment\nFix Version/s\nAdd Fix Version/s\nAdd label\nUpdate Epic\nChange assignee\nChange QA Contact\n' | fzf --prompt="Operation > " --height=40% --reverse --border)
  if [ -z "$OPERATION" ]; then
    echo "No operation selected. Aborting."
    return 1
  fi

  if [ "$OPERATION" = "Add comment" ]; then
    local -a COMMENT_LINES
    local COMMENT_LINE COMMENT_BODY
    COMMENT_LINES=()
    echo "Comment > (multiline; type EOF on a new line to finish)"
    while true; do
      IFS= read -r COMMENT_LINE
      if [ "$COMMENT_LINE" = "EOF" ]; then
        break
      fi
      COMMENT_LINES+=("$COMMENT_LINE")
    done
    COMMENT_BODY="${(j:\n:)COMMENT_LINES}"
    if [ -z "$COMMENT_BODY" ]; then
      echo "Comment is required. Aborting."
      return 1
    fi

    local COMMENT_RESPONSE COMMENT_HTTP_STATUS
    COMMENT_RESPONSE=$(curl -sS -w '\n%{http_code}' --request POST \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT/comment" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --arg body "$COMMENT_BODY" '{body: $body}')") || {
      echo "Error: Failed to add a comment to $ISSUE_INPUT."
      return 1
    }
    COMMENT_HTTP_STATUS="${COMMENT_RESPONSE##*$'\n'}"

    if [[ "$COMMENT_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully added a comment to $ISSUE_INPUT."
    else
      echo "Failed to add a comment to $ISSUE_INPUT (HTTP $COMMENT_HTTP_STATUS)."
      printf '%s\n' "${COMMENT_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${COMMENT_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  if [ "$OPERATION" = "Add label" ]; then
    local LABEL_LABELS EXISTING_LABEL NEW_LABEL LABEL_RESPONSE LABEL_HTTP_STATUS
    local -a EXISTING_LABELS
    EXISTING_LABELS=(${(f)$(printf '%s' "$ISSUE_RESPONSE" | jq -r '.fields.labels[]? // empty' 2>/dev/null)})
    if [ ${#EXISTING_LABELS[@]} -gt 0 ]; then
      echo "Existing labels: ${(j:, :)EXISTING_LABELS}"
    else
      echo "Existing labels: none"
    fi

    echo -n "New label > "
    read -r NEW_LABEL
    if [ -z "$NEW_LABEL" ]; then
      echo "Label is required. Aborting."
      return 1
    fi
    if (( ${EXISTING_LABELS[(Ie)$NEW_LABEL]} > 0 )); then
      echo "Label '$NEW_LABEL' already exists on $ISSUE_INPUT."
      return 1
    fi

    local LABELS_PAYLOAD='[]'
    local EXISTING_LABEL_VALUE
    for EXISTING_LABEL_VALUE in "${EXISTING_LABELS[@]}"; do
      LABELS_PAYLOAD=$(printf '%s' "$LABELS_PAYLOAD" | jq --arg label "$EXISTING_LABEL_VALUE" '. + [$label]')
    done
    LABELS_PAYLOAD=$(printf '%s' "$LABELS_PAYLOAD" | jq --arg label "$NEW_LABEL" '. + [$label]')

    LABEL_RESPONSE=$(curl -sS -w '\n%{http_code}' --request PUT \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --argjson labels "$LABELS_PAYLOAD" '{fields: {labels: $labels}}')") || {
      echo "Error: Failed to add label to $ISSUE_INPUT."
      return 1
    }
    LABEL_HTTP_STATUS="${LABEL_RESPONSE##*$'\n'}"

    if [[ "$LABEL_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully added label '$NEW_LABEL' to $ISSUE_INPUT."
    else
      echo "Failed to add label to $ISSUE_INPUT (HTTP $LABEL_HTTP_STATUS)."
      printf '%s\n' "${LABEL_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${LABEL_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  if [ "$OPERATION" = "Update Epic" ]; then
    local EPIC_LINK_FIELD_ID EPIC_ROWS SELECTED_EPIC EPIC_KEY EPIC_SUMMARY
    EPIC_LINK_FIELD_ID=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/field" 2>/dev/null \
      | jq -r '.[] | select(.name == "Epic Link") | .id' | head -n 1)
    if [ -z "$EPIC_LINK_FIELD_ID" ] || [ "$EPIC_LINK_FIELD_ID" = "null" ]; then
      echo "Could not locate the Epic Link field."
      return 1
    fi

    EPIC_ROWS=$(_create_ticket_eligible_epics "CLSTR")
    if [ -z "$EPIC_ROWS" ]; then
      echo "No eligible open or in-progress epics found."
      return 1
    fi

    SELECTED_EPIC=$(printf '%s\n' "$EPIC_ROWS" | fzf --prompt="Epic > " --height=60% --reverse --border --delimiter=$'\t' --with-nth=1,2,3,4)
    if [ -z "$SELECTED_EPIC" ]; then
      echo "No epic selected. Aborting."
      return 1
    fi
    EPIC_KEY="${SELECTED_EPIC%%$'\t'*}"
    local EPIC_REST="${SELECTED_EPIC#*$'\t'}"
    EPIC_REST="${EPIC_REST#*$'\t'}"
    EPIC_SUMMARY="${EPIC_REST#*$'\t'}"

    local EPIC_RESPONSE EPIC_HTTP_STATUS
    EPIC_RESPONSE=$(curl -sS -w '\n%{http_code}' --request PUT \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --arg field "$EPIC_LINK_FIELD_ID" --arg epic "$EPIC_KEY" '{fields: {($field): $epic}}')")
    EPIC_HTTP_STATUS="${EPIC_RESPONSE##*$'\n'}"

    if [[ "$EPIC_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully updated $ISSUE_INPUT with Epic $EPIC_KEY."
    else
      echo "Failed to update Epic for $ISSUE_INPUT (HTTP $EPIC_HTTP_STATUS)."
      printf '%s\n' "${EPIC_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${EPIC_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  if [ "$OPERATION" = "Change QA Contact" ]; then
    local PROJECT_KEY QA_QUERY QA_ROWS SELECTED_QA QA_KEY QA_NAME
    PROJECT_KEY="${ISSUE_INPUT%%-*}"
    echo -n "QA Contact search (at least 2 letters) > "
    read -r QA_QUERY
    if [ ${#QA_QUERY} -lt 2 ]; then
      echo "Enter at least 2 letters to search for a QA Contact."
      return 1
    fi

    echo "Searching assignable users in $PROJECT_KEY..."
    QA_ROWS=$(_jira_assignable_users "$QA_QUERY" "$PROJECT_KEY")
    if [ -z "$QA_ROWS" ]; then
      echo "No assignable users found for '$QA_QUERY'."
      return 1
    fi

    SELECTED_QA=$(printf '%s\n' "$QA_ROWS" | fzf --prompt="QA Contact > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2,3)
    if [ -z "$SELECTED_QA" ]; then
      echo "No QA Contact selected. Aborting."
      return 1
    fi
    QA_KEY="${SELECTED_QA%%$'\t'*}"
    local QA_REST="${SELECTED_QA#*$'\t'}"
    QA_NAME="${QA_REST%%$'\t'*}"

    local QA_RESPONSE QA_HTTP_STATUS
    QA_RESPONSE=$(curl -sS -w '\n%{http_code}' --request PUT \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --arg qa "$QA_KEY" '{fields: {customfield_10860: {name: $qa}}}')") || {
      echo "Error: Failed to change QA Contact for $ISSUE_INPUT."
      return 1
    }
    QA_HTTP_STATUS="${QA_RESPONSE##*$'\n'}"

    if [[ "$QA_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully assigned QA Contact for $ISSUE_INPUT to $QA_NAME."
    else
      echo "Failed to change QA Contact for $ISSUE_INPUT (HTTP $QA_HTTP_STATUS)."
      printf '%s\n' "${QA_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${QA_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  if [ "$OPERATION" = "Change assignee" ]; then
    local PROJECT_KEY ASSIGNEE_QUERY ASSIGNEE_ROWS SELECTED_ASSIGNEE ASSIGNEE_KEY ASSIGNEE_NAME
    PROJECT_KEY="${ISSUE_INPUT%%-*}"
    echo -n "Assignee search (at least 2 letters) > "
    read -r ASSIGNEE_QUERY
    if [ ${#ASSIGNEE_QUERY} -lt 2 ]; then
      echo "Enter at least 2 letters to search for an assignee."
      return 1
    fi

    echo "Searching assignable users in $PROJECT_KEY..."
    ASSIGNEE_ROWS=$(_jira_assignable_users "$ASSIGNEE_QUERY" "$PROJECT_KEY")
    if [ -z "$ASSIGNEE_ROWS" ]; then
      echo "No assignable users found for '$ASSIGNEE_QUERY'."
      return 1
    fi

    SELECTED_ASSIGNEE=$(printf '%s\n' "$ASSIGNEE_ROWS" | fzf --prompt="Assignee > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2,3)
    if [ -z "$SELECTED_ASSIGNEE" ]; then
      echo "No assignee selected. Aborting."
      return 1
    fi
    ASSIGNEE_KEY="${SELECTED_ASSIGNEE%%$'\t'*}"
    local ASSIGNEE_REST="${SELECTED_ASSIGNEE#*$'\t'}"
    ASSIGNEE_NAME="${ASSIGNEE_REST%%$'\t'*}"

    local ASSIGNEE_RESPONSE ASSIGNEE_HTTP_STATUS
    ASSIGNEE_RESPONSE=$(curl -sS -w '\n%{http_code}' --request PUT \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --arg assignee "$ASSIGNEE_KEY" '{fields: {assignee: {name: $assignee}}}')") || {
      echo "Error: Failed to change assignee for $ISSUE_INPUT."
      return 1
    }
    ASSIGNEE_HTTP_STATUS="${ASSIGNEE_RESPONSE##*$'\n'}"

    if [[ "$ASSIGNEE_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully assigned $ISSUE_INPUT to $ASSIGNEE_NAME."
    else
      echo "Failed to change assignee for $ISSUE_INPUT (HTTP $ASSIGNEE_HTTP_STATUS)."
      printf '%s\n' "${ASSIGNEE_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${ASSIGNEE_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  if [ "$OPERATION" = "Add Fix Version/s" ]; then
    local PROJECT_KEY VERSION_OPTIONS EXISTING_VERSION_IDS EXISTING_VERSION_NAMES
    local SELECTED_VERSION VERSION_ID VERSION_NAME SELECTED_ID
    local -a EXISTING_VERSION_ID_LIST ADD_VERSION_IDS ADD_VERSION_NAMES
    PROJECT_KEY="${ISSUE_INPUT%%-*}"

    EXISTING_VERSION_IDS=$(printf '%s' "$ISSUE_RESPONSE" | jq -r '.fields.fixVersions[]?.id // empty' 2>/dev/null)
    EXISTING_VERSION_NAMES=$(printf '%s' "$ISSUE_RESPONSE" | jq -r '.fields.fixVersions[]?.name // empty' 2>/dev/null)
    echo "Existing Fix Version/s: $(printf '%s\n' "$EXISTING_VERSION_NAMES" | paste -sd ', ' -)"

    VERSION_OPTIONS=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY/versions" 2>/dev/null \
      | jq -r '.[]? | select(.archived != true) | [(.id // ""), (.name // "Unknown")] | @tsv' 2>/dev/null)
    if [ -z "$VERSION_OPTIONS" ]; then
      echo "No selectable versions found for $PROJECT_KEY."
      return 1
    fi

    EXISTING_VERSION_ID_LIST=(${(f)EXISTING_VERSION_IDS})
    ADD_VERSION_IDS=()
    ADD_VERSION_NAMES=()
    while true; do
      local AVAILABLE_VERSION_OPTIONS=""
      while IFS=$'\t' read -r VERSION_ID VERSION_NAME; do
        [ -z "$VERSION_ID" ] && continue
        if (( ${EXISTING_VERSION_ID_LIST[(Ie)$VERSION_ID]} == 0 )) && (( ${ADD_VERSION_IDS[(Ie)$VERSION_ID]} == 0 )); then
          AVAILABLE_VERSION_OPTIONS+="${VERSION_ID}\t${VERSION_NAME}\n"
        fi
      done <<< "$VERSION_OPTIONS"

      if [ -z "$AVAILABLE_VERSION_OPTIONS" ]; then
        echo "No additional versions are available."
        break
      fi

      SELECTED_VERSION=$(printf '%b' "$AVAILABLE_VERSION_OPTIONS" | fzf --prompt="Add Fix Version/s > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2)
      if [ -z "$SELECTED_VERSION" ]; then
        echo "No version selected. Aborting."
        return 1
      fi
      SELECTED_ID="${SELECTED_VERSION%%$'\t'*}"
      VERSION_NAME="${SELECTED_VERSION#*$'\t'}"
      ADD_VERSION_IDS+=("$SELECTED_ID")
      ADD_VERSION_NAMES+=("$VERSION_NAME")

      local ADD_ANOTHER_VERSION
      ADD_ANOTHER_VERSION=$(printf 'No\nYes\n' | fzf --prompt="Add another Fix Version/s? > " --height=40% --reverse --border)
      [ "$ADD_ANOTHER_VERSION" != "Yes" ] && break
    done

    if [ ${#ADD_VERSION_IDS[@]} -eq 0 ]; then
      echo "No new Fix Version/s selected. Aborting."
      return 1
    fi

    local FIX_VERSIONS_PAYLOAD='[]'
    local EXISTING_VERSION_ID ADD_VERSION_ID
    while IFS= read -r EXISTING_VERSION_ID; do
      [ -n "$EXISTING_VERSION_ID" ] && FIX_VERSIONS_PAYLOAD=$(printf '%s' "$FIX_VERSIONS_PAYLOAD" | jq --arg id "$EXISTING_VERSION_ID" '. + [{id: $id}]')
    done <<< "$EXISTING_VERSION_IDS"
    for ADD_VERSION_ID in "${ADD_VERSION_IDS[@]}"; do
      FIX_VERSIONS_PAYLOAD=$(printf '%s' "$FIX_VERSIONS_PAYLOAD" | jq --arg id "$ADD_VERSION_ID" '. + [{id: $id}]')
    done

    local ADD_VERSION_RESPONSE ADD_VERSION_HTTP_STATUS
    ADD_VERSION_RESPONSE=$(curl -sS -w '\n%{http_code}' --request PUT \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --argjson fix_versions "$FIX_VERSIONS_PAYLOAD" '{fields: {fixVersions: $fix_versions}}')") || {
      echo "Error: Failed to append Fix Version/s for $ISSUE_INPUT."
      return 1
    }
    ADD_VERSION_HTTP_STATUS="${ADD_VERSION_RESPONSE##*$'\n'}"

    if [[ "$ADD_VERSION_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully appended Fix Version/s to $ISSUE_INPUT: ${(j:, :)ADD_VERSION_NAMES}"
    else
      echo "Failed to append Fix Version/s for $ISSUE_INPUT (HTTP $ADD_VERSION_HTTP_STATUS)."
      printf '%s\n' "${ADD_VERSION_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${ADD_VERSION_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  if [ "$OPERATION" = "Fix Version/s" ]; then
    local PROJECT_KEY VERSION_OPTIONS SELECTED_VERSION VERSION_ID VERSION_NAME
    local -a FIX_VERSION_IDS FIX_VERSION_NAMES
    PROJECT_KEY="${ISSUE_INPUT%%-*}"
    VERSION_OPTIONS=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY/versions" 2>/dev/null \
      | jq -r '.[]? | select(.archived != true) | [(.id // ""), (.name // "Unknown")] | @tsv' 2>/dev/null)
    if [ -z "$VERSION_OPTIONS" ]; then
      echo "No selectable versions found for $PROJECT_KEY."
      return 1
    fi

    FIX_VERSION_IDS=()
    FIX_VERSION_NAMES=()
    while true; do
      local AVAILABLE_VERSION_OPTIONS=""
      local selected_id
      while IFS=$'\t' read -r VERSION_ID VERSION_NAME; do
        [ -z "$VERSION_ID" ] && continue
        if (( ${FIX_VERSION_IDS[(Ie)$VERSION_ID]} == 0 )); then
          AVAILABLE_VERSION_OPTIONS+="${VERSION_ID}\t${VERSION_NAME}\n"
        fi
      done <<< "$VERSION_OPTIONS"
      if [ -z "$AVAILABLE_VERSION_OPTIONS" ]; then
        echo "All available versions have been selected."
        break
      fi

      SELECTED_VERSION=$(printf '%b' "$AVAILABLE_VERSION_OPTIONS" | fzf --prompt="Fix Version/s > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2)
      if [ -z "$SELECTED_VERSION" ]; then
        echo "No version selected. Aborting."
        return 1
      fi
      selected_id="${SELECTED_VERSION%%$'\t'*}"
      VERSION_NAME="${SELECTED_VERSION#*$'\t'}"
      FIX_VERSION_IDS+=("$selected_id")
      FIX_VERSION_NAMES+=("$VERSION_NAME")

      local ADD_ANOTHER_VERSION
      ADD_ANOTHER_VERSION=$(printf 'No\nYes\n' | fzf --prompt="Add another Fix Version/s? > " --height=40% --reverse --border)
      [ "$ADD_ANOTHER_VERSION" != "Yes" ] && break
    done

    local FIX_VERSIONS_PAYLOAD='[]'
    local selected_version_id
    for selected_version_id in "${FIX_VERSION_IDS[@]}"; do
      FIX_VERSIONS_PAYLOAD=$(printf '%s' "$FIX_VERSIONS_PAYLOAD" | jq --arg id "$selected_version_id" '. + [{id: $id}]')
    done

    local FIX_VERSION_RESPONSE FIX_VERSION_HTTP_STATUS
    FIX_VERSION_RESPONSE=$(curl -sS -w '\n%{http_code}' --request PUT \
      --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT" \
      --header "Authorization: Bearer $JIRA_TOKEN" \
      --header "Content-Type: application/json" \
      --data "$(jq -n --argjson fix_versions "$FIX_VERSIONS_PAYLOAD" '{fields: {fixVersions: $fix_versions}}')") || {
      echo "Error: Failed to update Fix Version/s for $ISSUE_INPUT."
      return 1
    }
    FIX_VERSION_HTTP_STATUS="${FIX_VERSION_RESPONSE##*$'\n'}"

    if [[ "$FIX_VERSION_HTTP_STATUS" = 2[0-9][0-9] ]]; then
      echo "Successfully updated Fix Version/s for $ISSUE_INPUT: ${(j:, :)FIX_VERSION_NAMES}"
    else
      echo "Failed to update Fix Version/s for $ISSUE_INPUT (HTTP $FIX_VERSION_HTTP_STATUS)."
      printf '%s\n' "${FIX_VERSION_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${FIX_VERSION_RESPONSE%$'\n'*}"
      return 1
    fi
    return 0
  fi

  local TRANSITIONS_RESPONSE
  TRANSITIONS_RESPONSE=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT/transitions?expand=transitions.fields" 2>/dev/null) || {
    echo "Error: Could not fetch available transitions for $ISSUE_INPUT."
    return 1
  }

  local TRANSITION_ROWS
  TRANSITION_ROWS=$(printf '%s' "$TRANSITIONS_RESPONSE" | jq -r '.transitions[]? | [(.id | tostring), (.name // "Unknown"), (.to.name // "Unknown")] | @tsv' 2>/dev/null)
  if [ -z "$TRANSITION_ROWS" ]; then
    echo "No available transitions from '$CURRENT_STATUS' for $ISSUE_INPUT."
    return 1
  fi

  local SELECTED_TRANSITION TRANSITION_ID TRANSITION_NAME TARGET_STATUS
  SELECTED_TRANSITION=$(printf '%s\n' "$TRANSITION_ROWS" | fzf --prompt="Next status > " --height=40% --reverse --border --delimiter=$'\t' --with-nth=2,3)
  if [ -z "$SELECTED_TRANSITION" ]; then
    echo "No transition selected. Aborting."
    return 1
  fi

  TRANSITION_ID="${SELECTED_TRANSITION%%$'\t'*}"
  local TRANSITION_REST="${SELECTED_TRANSITION#*$'\t'}"
  TRANSITION_NAME="${TRANSITION_REST%%$'\t'*}"
  TARGET_STATUS="${TRANSITION_REST#*$'\t'}"

  local TRANSITION_FIELDS_JSON
  TRANSITION_FIELDS_JSON=$(printf '%s' "$TRANSITIONS_RESPONSE" | jq -c --arg id "$TRANSITION_ID" '
    .transitions[]? | select((.id | tostring) == $id) | (.fields // {})
  ' 2>/dev/null)
  [ -z "$TRANSITION_FIELDS_JSON" ] && TRANSITION_FIELDS_JSON='{}'

  local TRANSITION_FIELD_ROWS
  TRANSITION_FIELD_ROWS=$(printf '%s' "$TRANSITION_FIELDS_JSON" | jq -r '
    to_entries[]
    | select(.value.required == true)
    | [ .key, (.value.name // .key), (.value.schema.type // "string"), (.value.schema.items // ""), ((.value.allowedValues // []) | length | tostring) ]
    | @tsv
  ' 2>/dev/null)

  local TRANSITION_FIELDS_PAYLOAD='{}'
  local FIELD_ID FIELD_LABEL FIELD_TYPE FIELD_ITEMS FIELD_OPTION_COUNT
  local FIELD_OPTIONS SELECTED_OPTION SELECTED_ID SELECTED_VALUE FIELD_VALUE
  local FIELD_ROWS FIELD_QUERY FIELD_RESPONSE PROJECT_KEY
  PROJECT_KEY="${ISSUE_INPUT%%-*}"

  while IFS=$'\t' read -r FIELD_ID FIELD_LABEL FIELD_TYPE FIELD_ITEMS FIELD_OPTION_COUNT; do
    [ -z "$FIELD_ID" ] && continue
    FIELD_OPTIONS=$(printf '%s' "$TRANSITION_FIELDS_JSON" | jq -r --arg field_id "$FIELD_ID" '
      .[$field_id].allowedValues[]?
      | [(.id // ""), (.name // .value // .displayName // .key // "Unknown")]
      | @tsv
    ' 2>/dev/null)

    if [ -z "$FIELD_OPTIONS" ] && [[ "$FIELD_TYPE" = "version" || "$FIELD_ITEMS" = "version" || "$FIELD_ID" = "versions" || "$FIELD_ID" = "fixVersions" ]]; then
      FIELD_OPTIONS=$(curl -fsS -H "Authorization: Bearer $JIRA_TOKEN" \
        "${JIRA_BASE_URL}/rest/api/2/project/$PROJECT_KEY/versions" 2>/dev/null \
        | jq -r '.[]? | select(.archived != true) | [(.id // ""), (.name // "Unknown")] | @tsv' 2>/dev/null)
    fi

    if [ -n "$FIELD_OPTIONS" ]; then
      SELECTED_OPTION=$(printf '%s\n' "$FIELD_OPTIONS" | fzf --prompt="$FIELD_LABEL > " --height=50% --reverse --border --delimiter=$'\t' --with-nth=2)
      if [ -z "$SELECTED_OPTION" ]; then
        echo "No value selected for '$FIELD_LABEL'. Aborting."
        return 1
      fi
      SELECTED_ID="${SELECTED_OPTION%%$'\t'*}"
      SELECTED_VALUE="${SELECTED_OPTION#*$'\t'}"
    else
      echo -n "$FIELD_LABEL > "
      read -r SELECTED_VALUE
      if [ -z "$SELECTED_VALUE" ]; then
        echo "Value required for '$FIELD_LABEL'. Aborting."
        return 1
      fi
      SELECTED_ID=""
    fi

    if [ "$FIELD_TYPE" = "array" ]; then
      if [ "$FIELD_ITEMS" = "version" ] || [ "$FIELD_ITEMS" = "component" ]; then
        if [ -n "$SELECTED_ID" ]; then
          FIELD_VALUE=$(jq -n --arg id "$SELECTED_ID" '[{id: $id}]')
        else
          FIELD_VALUE=$(jq -n --arg name "$SELECTED_VALUE" '[{name: $name}]')
        fi
      elif [ "$FIELD_ITEMS" = "option" ]; then
        FIELD_VALUE=$(jq -n --arg name "$SELECTED_VALUE" '[{name: $name}]')
      else
        FIELD_VALUE=$(jq -n --arg value "$SELECTED_VALUE" '[ $value ]')
      fi
    elif [ "$FIELD_TYPE" = "option" ]; then
      if [ -n "$SELECTED_ID" ]; then
        FIELD_VALUE=$(jq -n --arg id "$SELECTED_ID" '{id: $id}')
      else
        FIELD_VALUE=$(jq -n --arg name "$SELECTED_VALUE" '{name: $name}')
      fi
    elif [ "$FIELD_TYPE" = "version" ] || [ "$FIELD_TYPE" = "component" ]; then
      if [ -n "$SELECTED_ID" ]; then
        FIELD_VALUE=$(jq -n --arg id "$SELECTED_ID" '{id: $id}')
      else
        FIELD_VALUE=$(jq -n --arg name "$SELECTED_VALUE" '{name: $name}')
      fi
    elif [ "$FIELD_TYPE" = "user" ]; then
      if [ -n "$SELECTED_ID" ]; then
        FIELD_VALUE=$(jq -n --arg name "$SELECTED_ID" '{name: $name}')
      else
        FIELD_VALUE=$(jq -n --arg name "$SELECTED_VALUE" '{name: $name}')
      fi
    else
      FIELD_VALUE=$(jq -n --arg value "$SELECTED_VALUE" '$value')
    fi
    TRANSITION_FIELDS_PAYLOAD=$(printf '%s' "$TRANSITION_FIELDS_PAYLOAD" | jq --arg field_id "$FIELD_ID" --argjson value "$FIELD_VALUE" '. + {($field_id): $value}')
  done <<< "$TRANSITION_FIELD_ROWS"

  local CONFIRMATION
  CONFIRMATION=$(printf 'Change to %s\nCancel\n' "$TARGET_STATUS" | fzf --prompt="Confirm transition '$TRANSITION_NAME' > " --height=40% --reverse --border)
  if [ "$CONFIRMATION" != "Change to $TARGET_STATUS" ]; then
    echo "Ticket update cancelled."
    return 1
  fi

  local UPDATE_RESPONSE HTTP_STATUS
  UPDATE_RESPONSE=$(curl -sS -w '\n%{http_code}' --request POST \
    --url "${JIRA_BASE_URL}/rest/api/2/issue/$ISSUE_INPUT/transitions" \
    --header "Authorization: Bearer $JIRA_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$(jq -n --arg id "$TRANSITION_ID" --argjson fields "$TRANSITION_FIELDS_PAYLOAD" '{transition: {id: $id}, fields: $fields}')") || {
    echo "Error: Failed to update $ISSUE_INPUT."
    return 1
  }
  HTTP_STATUS="${UPDATE_RESPONSE##*$'\n'}"

  if [[ "$HTTP_STATUS" = 2[0-9][0-9] ]]; then
    echo "Successfully changed $ISSUE_INPUT from '$CURRENT_STATUS' to '$TARGET_STATUS'."
  else
    echo "Failed to update $ISSUE_INPUT (HTTP $HTTP_STATUS)."
    printf '%s\n' "${UPDATE_RESPONSE%$'\n'*}" | jq . 2>/dev/null || printf '%s\n' "${UPDATE_RESPONSE%$'\n'*}"
    return 1
  fi
}

# ------------------------------------------------------------------------------
# List Resolved Tickets
# Search and list tickets resolved by the current user within a specific timeframe.
# Usage: my_resolved_tickets [TIMEFRAME] (e.g., 30d, 12m, 1y. Default: 12m)
# ------------------------------------------------------------------------------
my_resolved_tickets() {
  _jira_validate_env || return 1

  local TIMEFRAME="${1:-12m}"
  local VALUE="${TIMEFRAME%[a-zA-Z]*}"
  local UNIT="${TIMEFRAME#$VALUE}"
  local JQL_TIME=""

  # Validate relative timeframe format for JQL
  case "$UNIT" in
    d|D) JQL_TIME="-${VALUE}d" ;;
    m|M) JQL_TIME="-${VALUE}m" ;;
    w|W) JQL_TIME="-${VALUE}w" ;;
    y|Y) JQL_TIME="-${VALUE}y" ;;
    *)
      echo "Error: Invalid timeframe format '$TIMEFRAME'."
      echo "Usage: my_resolved_tickets [TIMEFRAME]"
      echo "Examples: my_resolved_tickets 30d | my_resolved_tickets 6m | my_resolved_tickets 1y"
      return 1
      ;;
  esac

  echo "Fetching tickets resolved by you in the last $TIMEFRAME..."
  echo "================================================================================"

  # Construct and URL-encode JQL query
  # Use resolutiondate to find tickets resolved by the current user
  local JQL="resolution IS NOT EMPTY AND resolutiondate >= $JQL_TIME AND assignee = currentUser() ORDER BY resolutiondate DESC"
  local ENCODED_JQL=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$JQL")

  local RESPONSE
  RESPONSE=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&maxResults=500&fields=key,summary,updated,status,resolution,resolutiondate")

  if printf '%s' "$RESPONSE" | jq -e '.errorMessages' > /dev/null 2>&1; then
    echo "❌ Error fetching tickets:"
    printf '%s' "$RESPONSE" | jq -r '.errorMessages[]'
    return 1
  fi

  # Output table view of resolved tickets
  printf '%s' "$RESPONSE" | jq -r '
    .issues[] | "\(.key)\t|\t\(.fields.resolutiondate[0:10])\t|\t\(.fields.resolution?.name // "Unknown")\t|\t\(.fields.summary)"
  ' | column -t -s $'\t'

  local TOTAL
  TOTAL=$(printf '%s' "$RESPONSE" | jq -r '.total')
  echo "================================================================================"
  echo "Total resolved ($TIMEFRAME): $TOTAL"
}

# ------------------------------------------------------------------------------
# List Filed Tickets
# Search and list tickets reported/created by the current user within a specific timeframe.
# Usage: my_filed_tickets [TIMEFRAME] (e.g., 30d, 12m, 1y. Default: 12m)
# ------------------------------------------------------------------------------
my_filed_tickets() {
  _jira_validate_env || return 1
  emulate -L zsh
  local TIMEFRAME="${1:-12m}"
  
  local VALUE="${TIMEFRAME%%[a-zA-Z]*}"
  local UNIT="${(L)TIMEFRAME#$VALUE}"
  local JQL_TIME=""

  # Convert units into Jira-compatible relative durations
  case "$UNIT" in
    d) JQL_TIME="-${VALUE}d" ;;
    w) JQL_TIME="-${VALUE}w" ;;
    h) JQL_TIME="-${VALUE}h" ;;
    m) JQL_TIME="-$(( VALUE * 30 ))d" ;;  # Convert months to days (1m = 30d)
    y) JQL_TIME="-$(( VALUE * 365 ))d" ;; # Convert years to days (1y = 365d)
    *)
      echo "Error: Invalid timeframe format '$TIMEFRAME'."
      echo "Usage: my_filed_tickets [TIMEFRAME]"
      echo "Examples: my_filed_tickets 30d | my_filed_tickets 6m | my_filed_tickets 1y"
      return 1
      ;;
  esac

  echo "Fetching tickets filed by you in the last $TIMEFRAME (JQL: created >= $JQL_TIME)..."
  echo "================================================================================"

  local JQL="reporter = currentUser() AND created >= $JQL_TIME ORDER BY created DESC"
  local ENCODED_JQL=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$JQL")

  local RESPONSE
  RESPONSE=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${ENCODED_JQL}&maxResults=500&fields=key,summary,created,status")

  if printf '%s' "$RESPONSE" | jq -e '.errorMessages' > /dev/null 2>&1; then
    echo "❌ Error fetching tickets:"
    printf '%s' "$RESPONSE" | jq -r '.errorMessages[]'
    return 1
  fi

  printf '%s' "$RESPONSE" | jq -r '
    .issues[] | "\(.key)\t|\t\(.fields.created[0:10])\t|\t\(.fields.status.name)\t|\t\(.fields.summary)"
  ' | column -t -s $'\t'

  local TOTAL
  TOTAL=$(printf '%s' "$RESPONSE" | jq -r '.total')
  echo "================================================================================"
  echo "Total filed ($TIMEFRAME): $TOTAL"
}

my_open_tickets() {
  _jira_validate_env || return 1

  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=assignee=currentUser()%20AND%20resolution=Unresolved%20ORDER%20BY%20priority%20DESC" \
    | jq -r '["KEY", "PRIORITY", "STATUS", "SUMMARY"], (.issues[] | [.key, .fields.priority.name, .fields.status.name, .fields.summary]) | @tsv' \
    | column -t -s $'\t'
}

show_epic_summary() {
  _jira_validate_env || return 1

  local epic_key="${1:-}"

  if [[ -z "$epic_key" ]]; then
    echo -n "Enter Epic Key (e.g., PROJECT-1234): "
    read -r epic_key
  fi

  if [[ -z "$epic_key" ]]; then
    echo "Error: Epic key is required."
    return 1
  fi

  epic_key=$(printf '%s' "$epic_key" | tr '[:lower:]' '[:upper:]')
  local encoded_epic_key
  encoded_epic_key=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$epic_key")

  curl -sS -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=%22Epic%20Link%22%20%3D%20${encoded_epic_key}%20ORDER%20BY%20priority%20DESC" \
    | jq -r '
      ["KEY", "PRIORITY", "STATUS", "SUMMARY"],
      (.issues[]? | [.key, (.fields.priority.name // "Unknown"), (.fields.status.name // "Unknown"), (.fields.summary // "")])
      | @tsv
    ' \
    | column -t -s $'\t'
}

# ------------------------------------------------------------------------------
# Completions for create_ticket
# Required args: PRIORITY TYPE COMPONENT TITLE DESCRIPTION
# ------------------------------------------------------------------------------
_create_ticket_issue_types() {
  _jira_validate_env || return 1

  local project_key="${1:-CLSTR}"
  local issue_types

  issue_types=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/issue/createmeta?projectKeys=${project_key}&expand=projects.issuetypes" \
    | jq -r '.projects[0].issuetypes[]? | select(.subtask != true) | .name' 2>/dev/null)

  if [ -n "$issue_types" ]; then
    echo "$issue_types"
    return 0
  fi

  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/project/${project_key}" \
    | jq -r '.issueTypes[]? | select(.subtask != true) | .name' 2>/dev/null
}

_create_ticket_components() {
  _jira_validate_env || return 1

  local project_key="${1:-CLSTR}"
  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/project/${project_key}/components" \
    | jq -r '.[].name' 2>/dev/null
}

_create_ticket_eligible_epics() {
  _jira_validate_env || return 1

  local project_key="${1:-CLSTR}"
  local epic_link_field_id
  epic_link_field_id=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/field" \
    | jq -r '.[] | select(.name == "Epic Link") | .id' 2>/dev/null | head -n 1)

  if [ -z "$epic_link_field_id" ] || [ "$epic_link_field_id" = "null" ]; then
    return 0
  fi

  local epic_link_field_num="${epic_link_field_id#customfield_}"
  local assigned_epics_jql="project in (CLSTR, ENG) AND issuetype = Epic AND statusCategory != Done AND assignee = currentUser() ORDER BY updated DESC"
  local assigned_epics_encoded
  assigned_epics_encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$assigned_epics_jql")

  local assigned_epics_response
  assigned_epics_response=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${assigned_epics_encoded}&maxResults=500&fields=key,summary,status,assignee")

  if printf '%s' "$assigned_epics_response" | jq -e '.errorMessages' >/dev/null 2>&1; then
    assigned_epics_response='{"issues":[]}'
  fi

  local my_issues_with_epic_jql="project in (CLSTR, ENG) AND assignee = currentUser() AND statusCategory != Done AND cf[${epic_link_field_num}] IS NOT EMPTY ORDER BY updated DESC"
  local my_issues_with_epic_encoded
  my_issues_with_epic_encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$my_issues_with_epic_jql")

  local my_issues_with_epic_response
  my_issues_with_epic_response=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
    "${JIRA_BASE_URL}/rest/api/2/search?jql=${my_issues_with_epic_encoded}&maxResults=500&fields=key,summary,${epic_link_field_id}")

  local related_epic_keys=()
  while IFS= read -r key; do
    [ -n "$key" ] && related_epic_keys+=("$key")
  done < <(printf '%s' "$my_issues_with_epic_response" | jq -r --arg epic_field "$epic_link_field_id" '.issues[]?.fields[$epic_field] // empty' 2>/dev/null | sort -u)

  local related_epics_response='{"issues":[]}'
  if [ ${#related_epic_keys[@]} -gt 0 ]; then
    local keys_csv=""
    local key
    for key in "${related_epic_keys[@]}"; do
      keys_csv="${keys_csv}'${key}',"
    done
    keys_csv="${keys_csv%,}"

    local related_epics_jql="project in (CLSTR, ENG) AND issuetype = Epic AND statusCategory != Done AND key IN (${keys_csv}) ORDER BY updated DESC"
    local related_epics_encoded
    related_epics_encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$related_epics_jql")

    related_epics_response=$(curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
      "${JIRA_BASE_URL}/rest/api/2/search?jql=${related_epics_encoded}&maxResults=500&fields=key,summary,status,assignee")
  fi

  local merged_responses
  merged_responses=$(jq -s '{issues: [.[0].issues[]?, .[1].issues[]?]}' \
    <(printf '%s' "$assigned_epics_response") \
    <(printf '%s' "$related_epics_response") 2>/dev/null)

  printf '%s' "$merged_responses" | jq -r '
    [(.issues[]? | {
      key: .key,
      status: (.fields.status.name // "N/A"),
      assignee: (.fields.assignee.displayName // "Unassigned"),
      summary: (.fields.summary // "")
    })] as $items
    | reduce $items[] as $item ({}; .[$item.key] = $item)
    | to_entries[]
    | "\(.value.key)\t\(.value.status)\t\(.value.assignee)\t\(.value.summary)"
  ' 2>/dev/null
}

_create_ticket() {
  emulate -L zsh
  local context state line ret=1
  typeset -A opt_args
  local project_key="${words[2]:u}"
  if [[ "$project_key" != "CLSTR" && "$project_key" != "ENG" ]]; then
    project_key="CLSTR"
  fi

  _arguments -C \
    '(-h --help)'{-h,--help}'[show help for create_ticket]' \
    '1:project:(CLSTR ENG)' \
    '2:priority:_message "priority name or ID"' \
    '3:ticket type:->issue_type' \
    '4:component:->component' \
    '5:title:_message "ticket title"' \
    '6:description:_message "ticket description"' \
    '7:assignee (optional):_message "jira username (optional)"' \
    '8:primary component (ENG):_message "primary component (ENG tickets only)"' \
    '9:epic key (optional):->epic' && ret=0

  case "$state" in
    issue_type)
      local -a issue_types
      issue_types=("${(@f)$(_create_ticket_issue_types "$project_key")}")
      if [ ${#issue_types[@]} -gt 0 ]; then
        _describe "issue type" issue_types && ret=0
      fi
      ;;
    component)
      local -a components
      components=("${(@f)$(_create_ticket_components "$project_key")}")
      if [ ${#components[@]} -gt 0 ]; then
        _describe "component" components && ret=0
      fi
      ;;
    epic)
      local -a epic_rows
      local -a epic_completions
      local row key status assignee summary
      epic_rows=("${(@f)$(_create_ticket_eligible_epics "$project_key")}")
      if [ ${#epic_rows[@]} -gt 0 ]; then
        for row in "${epic_rows[@]}"; do
          key="${row%%$'\t'*}"
          local rest="${row#*$'\t'}"
          status="${rest%%$'\t'*}"
          rest="${rest#*$'\t'}"
          assignee="${rest%%$'\t'*}"
          summary="${rest#*$'\t'}"
          epic_completions+=("${key}:${status} | ${assignee} | ${summary}")
        done
        _describe "eligible in-progress epic" epic_completions && ret=0
      fi
      ;;
  esac

  return ret
}

if (( $+functions[compdef] )); then
  compdef _create_ticket create_ticket
fi
