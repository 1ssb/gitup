#!/bin/bash
# gitup - Comprehensive Git update script for repositories and submodules
# Created: April 22, 2025
# Author: GitHub Copilot and 1ssb
set -e  # Exit on error

# Colors for better output readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored section headers
section() {
  echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# Function to print success messages
success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error messages
error() {
  echo -e "${RED}✗ $1${NC}" >&2
}

# Function to print warnings
warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Function to print info messages
info() {
  echo -e "${CYAN}ℹ $1${NC}"
}

# Function to check if directory is a git repository
is_git_repo() {
  if [ -d "$1/.git" ] || git -C "$1" rev-parse --git-dir > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Function to handle a single git repository
handle_repo() {
  local repo_path="$1"
  local repo_name=$(basename "$repo_path")
  
  # Change to repository directory
  cd "$repo_path"
  
  section "Processing repository: $repo_name ($(pwd))"
  
  # Check for uncommitted changes
  if ! git diff --quiet || ! git diff --staged --quiet; then
    info "Uncommitted changes detected in $repo_name"
    
    # Stash any changes if requested
    read -p "Would you like to stash changes before proceeding? [y/N] " stash_choice
    if [[ "$stash_choice" =~ ^[Yy]$ ]]; then
      git stash save "Auto-stashed by gitup $(date)"
      success "Changes stashed"
    fi
  fi
  
  # Add all files
  info "Adding all files..."
  git add -A
  
  # Check if there are changes to commit
  if ! git diff --staged --quiet; then
    # Prompt for commit message
    read -p "Enter commit message (leave blank for default message): " commit_msg
    
    if [ -z "$commit_msg" ]; then
      commit_msg="Auto-commit: $(date)"
    fi
    
    # Commit changes
    info "Committing changes with message: \"$commit_msg\""
    git commit -m "$commit_msg"
    success "Changes committed"
  else
    success "No changes to commit"
  fi
  
  # Check current branch
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
  info "Current branch: $current_branch"
  
  # Check if branch has upstream
  if git rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
    # Pull latest changes
    info "Pulling latest changes from remote..."
    git pull --ff-only || {
      warning "Cannot fast-forward. Trying to rebase..."
      git pull --rebase || {
        error "Could not pull changes. Please resolve conflicts manually."
        git rebase --abort 2>/dev/null || true
        return 1
      }
    }
    success "Pull successful"
    
    # Push changes
    info "Pushing changes to remote..."
    git push || {
      error "Failed to push changes to remote"
      return 1
    }
    success "Push successful"
  else
    warning "Branch '$current_branch' has no upstream. Skipping pull/push."
    
    # Offer to set upstream
    read -p "Would you like to set upstream and push? [y/N] " upstream_choice
    if [[ "$upstream_choice" =~ ^[Yy]$ ]]; then
      read -p "Enter remote name [origin]: " remote_name
      remote_name=${remote_name:-origin}
      
      # Set upstream and push
      info "Setting upstream to $remote_name/$current_branch and pushing..."
      git push --set-upstream "$remote_name" "$current_branch" || {
        error "Failed to push and set upstream"
        return 1
      }
      success "Upstream set and pushed successfully"
    fi
  fi
  
  return 0
}

# Function to recursively handle repositories and submodules
handle_recursive() {
  local start_path="$1"
  local depth="$2"
  
  # Initialize depth if not set
  if [ -z "$depth" ]; then
    depth=0
  fi
  
  # Check if directory exists
  if [ ! -d "$start_path" ]; then
    error "Directory does not exist: $start_path"
    return 1
  fi
  
  # Set indent for clearer output
  local indent=$(printf '%*s' "$depth" | tr ' ' '  ')
  
  # Process main repository if it's a git repo
  if is_git_repo "$start_path"; then
    handle_repo "$start_path" || {
      warning "Failed to process repository: $start_path"
    }
    
    # Check for git submodules
    if [ -f "$start_path/.gitmodules" ]; then
      section "Processing submodules for $(basename "$start_path")"
      
      # Update submodules
      info "Updating submodules..."
      git -C "$start_path" submodule update --init --recursive
      
      # Get submodule paths
      submodule_paths=$(git -C "$start_path" config --file .gitmodules --get-regexp path | awk '{ print $2 }')
      
      # Process each submodule
      for submodule_path in $submodule_paths; do
        full_path="$start_path/$submodule_path"
        
        if [ -d "$full_path" ]; then
          info "${indent}Processing submodule: $submodule_path"
          handle_recursive "$full_path" $((depth+1))
        else
          warning "${indent}Submodule directory not found: $submodule_path"
        fi
      done
    fi
  elif [ "$depth" -eq 0 ]; then
    # Only check subdirectories for git repos if we're at the top level
    # and the current directory is not a git repo itself
    section "Searching for git repositories in: $start_path"
    
    found_repos=0
    
    # Find git repositories in subdirectories (max depth 3)
    while IFS= read -r repo_dir; do
      repo_path=$(dirname "$repo_dir")
      if [ "$repo_path" != "$start_path/.git" ]; then  # Exclude the main .git directory
        found_repos=$((found_repos+1))
        handle_recursive "$repo_path" $((depth+1))
      fi
    done < <(find "$start_path" -maxdepth 3 -name ".git" -type d 2>/dev/null)
    
    if [ "$found_repos" -eq 0 ]; then
      warning "No git repositories found in: $start_path"
      return 1
    fi
  else
    warning "Directory is not a git repository: $start_path"
    return 1
  fi
  
  return 0
}

# Main function
main() {
  local start_path="."
  
  # Check if an argument is provided
  if [ $# -gt 0 ] && [ -d "$1" ]; then
    start_path="$1"
  fi
  
  start_path=$(realpath "$start_path")
  
  section "Git repository update - $(date)"
  info "Starting point: $start_path"
  
  handle_recursive "$start_path"
  
  section "Summary"
  success "Git update process completed!"
  
  return 0
}

# Run the main function with all arguments
main "$@"
