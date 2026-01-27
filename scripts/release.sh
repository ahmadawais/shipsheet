#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State file for tracking progress
STATE_FILE=".release-state"

# Step order
STEPS=(
  "init"
  "show_commits"
  "create_changeset"
  "build"
  "version"
  "git_commit"
  "npm_publish"
  "git_push"
  "gh_release"
  "cleanup"
)

#######################################
# PURE FUNCTIONS
#######################################

get_pkg_name() {
  node -p "require('./package.json').name"
}

get_pkg_version() {
  node -p "require('./package.json').version"
}

get_repo() {
  node -p "require('./package.json').repository.url.replace('git+', '').replace('.git', '').split('github.com/')[1]"
}

get_last_tag() {
  git describe --tags --abbrev=0 2>/dev/null || echo ""
}

get_commits_since_tag() {
  local tag=$1
  if [ -n "$tag" ]; then
    git log $tag..HEAD --pretty=format:"- %s"
  else
    git log --oneline -10 --pretty=format:"- %s"
  fi
}

get_current_commit() {
  git rev-parse HEAD
}

#######################################
# STATE MANAGEMENT
#######################################

save_state() {
  local key=$1
  local value=$2
  # Remove existing key if present
  if [ -f $STATE_FILE ]; then
    grep -v "^$key:" $STATE_FILE > "${STATE_FILE}.tmp" 2>/dev/null || true
    mv "${STATE_FILE}.tmp" $STATE_FILE
  fi
  echo "$key:$value" >> $STATE_FILE
}

get_state() {
  local key=$1
  grep "^$key:" $STATE_FILE 2>/dev/null | cut -d: -f2- || echo ""
}

clear_state() {
  rm -f $STATE_FILE
}

has_state() {
  [ -f $STATE_FILE ]
}

is_step_done() {
  local step=$1
  local done_steps=$(get_state "completed_steps")
  [[ ",$done_steps," == *",$step,"* ]]
}

mark_step_done() {
  local step=$1
  local done_steps=$(get_state "completed_steps")
  if [ -z "$done_steps" ]; then
    save_state "completed_steps" "$step"
  else
    save_state "completed_steps" "$done_steps,$step"
  fi
  save_state "last_step" "$step"
}

get_step_index() {
  local step=$1
  for i in "${!STEPS[@]}"; do
    if [[ "${STEPS[$i]}" == "$step" ]]; then
      echo $i
      return
    fi
  done
  echo -1
}

#######################################
# VERIFICATION FUNCTIONS
#######################################

verify_init() {
  [ -n "$(get_state 'original_commit')" ]
}

verify_show_commits() {
  [ -n "$(get_state 'last_tag')" ] || [ "$(get_state 'no_previous_tag')" = "true" ]
}

verify_create_changeset() {
  local file=$(get_state "changeset_file")
  [ -n "$file" ] && [ -f "$file" ]
}

verify_build() {
  [ -d "dist" ]
}

verify_version() {
  # Check if CHANGELOG was updated
  [ -f "CHANGELOG.md" ] && grep -q "$(get_pkg_version)" CHANGELOG.md
}

verify_git_commit() {
  local version=$(get_state "version")
  [ -n "$version" ] && git log -1 --pretty=%B | grep -q "RELEASE: v$version"
}

verify_npm_publish() {
  local pkg=$(get_pkg_name)
  local version=$(get_state "version")
  npm view "$pkg@$version" version 2>/dev/null | grep -q "$version"
}

verify_git_push() {
  local tag=$(get_state "tag")
  git ls-remote --tags origin | grep -q "refs/tags/$tag"
}

verify_gh_release() {
  local tag=$(get_state "tag")
  gh release view "$tag" &>/dev/null
}

verify_cleanup() {
  ! has_state
}

#######################################
# ROLLBACK FUNCTIONS
#######################################

rollback_git_commit() {
  local original_commit=$(get_state "original_commit")
  if [ -n "$original_commit" ]; then
    echo -e "${YELLOW}↩️  Rolling back to commit $original_commit${NC}"
    git reset --hard $original_commit
  fi
}

rollback_changeset() {
  local changeset_file=$(get_state "changeset_file")
  if [ -n "$changeset_file" ] && [ -f "$changeset_file" ]; then
    echo -e "${YELLOW}↩️  Removing changeset $changeset_file${NC}"
    rm -f "$changeset_file"
  fi
}

rollback_tag() {
  local tag=$(get_state "tag")
  if [ -n "$tag" ]; then
    echo -e "${YELLOW}↩️  Removing local tag $tag${NC}"
    git tag -d $tag 2>/dev/null || true
  fi
}

rollback_remote_tag() {
  local tag=$(get_state "tag")
  if [ -n "$tag" ]; then
    echo -e "${YELLOW}↩️  Removing remote tag $tag${NC}"
    git push origin :refs/tags/$tag 2>/dev/null || true
  fi
}

rollback_gh_release() {
  local tag=$(get_state "tag")
  if [ -n "$tag" ]; then
    echo -e "${YELLOW}↩️  Deleting GitHub release $tag${NC}"
    gh release delete $tag --yes 2>/dev/null || true
  fi
}

rollback() {
  echo -e "${RED}🚨 Rolling back...${NC}"
  
  local last_step=$(get_state "last_step")
  
  case $last_step in
    "gh_release")
      rollback_gh_release
      rollback_remote_tag
      rollback_git_commit
      ;;
    "git_push")
      rollback_remote_tag
      rollback_git_commit
      ;;
    "npm_publish")
      echo -e "${RED}⚠️  Cannot unpublish from npm automatically. Run: npm unpublish $(get_pkg_name)@$(get_state 'version')${NC}"
      rollback_git_commit
      ;;
    "git_commit")
      rollback_git_commit
      ;;
    "version")
      rollback_git_commit
      ;;
    "changeset")
      rollback_changeset
      ;;
    *)
      echo -e "${YELLOW}Nothing to rollback${NC}"
      ;;
  esac
  
  clear_state
  echo -e "${GREEN}✅ Rollback complete${NC}"
}

#######################################
# STEP FUNCTIONS
#######################################

step_init() {
  if is_step_done "init" && verify_init; then
    echo -e "${BLUE}⏭️  Skipping init (already done)${NC}"
    return 0
  fi
  
  echo -e "${GREEN}🚀 Starting release...${NC}"
  save_state "original_commit" "$(get_current_commit)"
  mark_step_done "init"
}

step_show_commits() {
  if is_step_done "show_commits" && verify_show_commits; then
    echo -e "${BLUE}⏭️  Skipping show_commits (already done)${NC}"
    return 0
  fi
  
  local last_tag=$(get_last_tag)
  echo ""
  echo -e "${GREEN}📝 Commits since last release ($last_tag):${NC}"
  echo "================================"
  get_commits_since_tag "$last_tag"
  echo ""
  echo "================================"
  
  if [ -n "$last_tag" ]; then
    save_state "last_tag" "$last_tag"
  else
    save_state "no_previous_tag" "true"
  fi
  mark_step_done "show_commits"
}

step_create_changeset() {
  if is_step_done "create_changeset" && verify_create_changeset; then
    echo -e "${BLUE}⏭️  Skipping create_changeset (already done)${NC}"
    return 0
  fi
  
  local pkg_name=$(get_pkg_name)
  local last_tag=$(get_state "last_tag")
  local commits=$(get_commits_since_tag "$last_tag")
  local filename=$(openssl rand -hex 4)
  local filepath=".changeset/$filename.md"
  
  mkdir -p .changeset
  cat > "$filepath" << EOF
---
"$pkg_name": patch
---

$commits
EOF
  
  echo -e "${GREEN}✅ Created changeset${NC}"
  save_state "changeset_file" "$filepath"
  mark_step_done "create_changeset"
}

step_build() {
  if is_step_done "build" && verify_build; then
    echo -e "${BLUE}⏭️  Skipping build (already done)${NC}"
    return 0
  fi
  
  echo -e "${GREEN}🔨 Building...${NC}"
  pnpm build
  mark_step_done "build"
}

step_version() {
  if is_step_done "version" && verify_version; then
    echo -e "${BLUE}⏭️  Skipping version (already done)${NC}"
    save_state "version" "$(get_pkg_version)"
    save_state "tag" "v$(get_pkg_version)"
    return 0
  fi
  
  echo -e "${GREEN}📦 Versioning...${NC}"
  pnpm changeset version
  save_state "version" "$(get_pkg_version)"
  save_state "tag" "v$(get_pkg_version)"
  mark_step_done "version"
}

step_git_commit() {
  if is_step_done "git_commit" && verify_git_commit; then
    echo -e "${BLUE}⏭️  Skipping git_commit (already done)${NC}"
    return 0
  fi
  
  local version=$(get_state "version")
  echo -e "${GREEN}💾 Committing v$version...${NC}"
  git add -A
  git commit -m "🚀 RELEASE: v$version"
  mark_step_done "git_commit"
}

step_npm_publish() {
  if is_step_done "npm_publish" && verify_npm_publish; then
    echo -e "${BLUE}⏭️  Skipping npm_publish (already done)${NC}"
    return 0
  fi
  
  echo -e "${GREEN}🚀 Publishing to npm...${NC}"
  pnpm changeset publish
  mark_step_done "npm_publish"
}

step_git_push() {
  if is_step_done "git_push" && verify_git_push; then
    echo -e "${BLUE}⏭️  Skipping git_push (already done)${NC}"
    return 0
  fi
  
  echo -e "${GREEN}📤 Pushing...${NC}"
  git push --follow-tags
  mark_step_done "git_push"
}

step_gh_release() {
  if is_step_done "gh_release" && verify_gh_release; then
    echo -e "${BLUE}⏭️  Skipping gh_release (already done)${NC}"
    return 0
  fi
  
  local version=$(get_state "version")
  local repo=$(get_repo)
  local tag="v$version"
  
  echo -e "${GREEN}🐙 Creating GitHub release...${NC}"
  gh release create $tag --generate-notes
  gh release edit $tag --notes "$(gh release view $tag --json body -q .body)

[Full Changelog](https://github.com/$repo/blob/main/CHANGELOG.md)"
  mark_step_done "gh_release"
}

step_cleanup() {
  clear_state
  local pkg_name=$(get_pkg_name)
  local version=$(get_pkg_version)
  echo ""
  echo -e "${GREEN}✅ Released $pkg_name@$version${NC}"
}

#######################################
# RUN SINGLE STEP
#######################################

run_step() {
  local step=$1
  case $step in
    "init") step_init ;;
    "show_commits") step_show_commits ;;
    "create_changeset") step_create_changeset ;;
    "build") step_build ;;
    "version") step_version ;;
    "git_commit") step_git_commit ;;
    "npm_publish") step_npm_publish ;;
    "git_push") step_git_push ;;
    "gh_release") step_gh_release ;;
    "cleanup") step_cleanup ;;
    *) echo -e "${RED}Unknown step: $step${NC}"; exit 1 ;;
  esac
}

run_from_step() {
  local start_step=$1
  local start_index=$(get_step_index "$start_step")
  
  if [ $start_index -eq -1 ]; then
    echo -e "${RED}Unknown step: $start_step${NC}"
    echo "Available steps: ${STEPS[*]}"
    exit 1
  fi
  
  for ((i=start_index; i<${#STEPS[@]}; i++)); do
    run_step "${STEPS[$i]}"
  done
}

#######################################
# RESUME
#######################################

resume() {
  if ! has_state; then
    echo -e "${YELLOW}No release in progress. Starting fresh...${NC}"
    run_from_step "init"
    return
  fi
  
  echo -e "${BLUE}📋 Resuming release...${NC}"
  local last_step=$(get_state "last_step")
  local last_index=$(get_step_index "$last_step")
  local next_index=$((last_index + 1))
  
  if [ $next_index -ge ${#STEPS[@]} ]; then
    echo -e "${GREEN}✅ Release already complete${NC}"
    clear_state
    return
  fi
  
  local next_step="${STEPS[$next_index]}"
  echo -e "${BLUE}Continuing from: $next_step${NC}"
  run_from_step "$next_step"
}

#######################################
# STATUS
#######################################

status() {
  if ! has_state; then
    echo -e "${YELLOW}No release in progress${NC}"
    return
  fi
  
  echo -e "${BLUE}📋 Release Status:${NC}"
  echo "================================"
  
  local completed=$(get_state "completed_steps")
  local version=$(get_state "version")
  local tag=$(get_state "tag")
  
  [ -n "$version" ] && echo "Version: $version"
  [ -n "$tag" ] && echo "Tag: $tag"
  echo ""
  
  for step in "${STEPS[@]}"; do
    if is_step_done "$step"; then
      echo -e "  ${GREEN}✅ $step${NC}"
    else
      echo -e "  ⬜ $step"
    fi
  done
  echo "================================"
}

#######################################
# HELP
#######################################

show_help() {
  echo "Usage: pnpm release [command] [options]"
  echo ""
  echo "Commands:"
  echo "  (none)        Run full release (resumes if incomplete)"
  echo "  --step <name> Run a specific step"
  echo "  --from <name> Run from a specific step onwards"
  echo "  --status      Show current release status"
  echo "  --rollback    Rollback incomplete release"
  echo "  --help        Show this help"
  echo ""
  echo "Steps: ${STEPS[*]}"
}

#######################################
# MAIN
#######################################

trap 'echo -e "${RED}❌ Release failed at step: $(get_state "last_step")${NC}"; echo "Run: pnpm release (to resume) or pnpm release --rollback"; exit 1' ERR

case "$1" in
  "--rollback")
    if has_state; then
      rollback
    else
      echo -e "${YELLOW}No release in progress to rollback${NC}"
    fi
    ;;
  "--status")
    status
    ;;
  "--step")
    if [ -z "$2" ]; then
      echo -e "${RED}Please specify a step${NC}"
      exit 1
    fi
    run_step "$2"
    ;;
  "--from")
    if [ -z "$2" ]; then
      echo -e "${RED}Please specify a step${NC}"
      exit 1
    fi
    run_from_step "$2"
    ;;
  "--help"|"-h")
    show_help
    ;;
  "")
    resume
    ;;
  *)
    echo -e "${RED}Unknown command: $1${NC}"
    show_help
    exit 1
    ;;
esac
