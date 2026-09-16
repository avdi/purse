#!/usr/bin/env ruby
# frozen_string_literal: true

# Mutating actions for the herd-prs pass, as reusable subcommands instead of
# hand-written GraphQL each time. Each subcommand does ONE thing — call this
# once per action, review what it did, don't chain blindly.
#
# Usage:
#   herd_prs_apply.rb move   <owner/repo> <number> <StatusName> [--issue]
#   herd_prs_apply.rb add    <owner/repo> <number> <StatusName> [--issue]
#   herd_prs_apply.rb assign <owner/repo> <number> <login> [--issue]
#   herd_prs_apply.rb comment <owner/repo> <number> <body-from-stdin>
#   herd_prs_apply.rb sync-branch <owner/repo> <number>
#
# `move` auto-detects whether `number` is tracked directly or via its linked
# issue — pass --issue only for a number that's an issue with no PR at all
# (e.g. a no-linked-PR item). `assign` always needs --issue to pick the right
# GitHub object (`gh issue edit` vs `gh pr edit`) — it can't guess.
#
# `add` puts an item onto the board for the first time (see "Orphan check" in
# SKILL.md) — `move` errors on anything not already there. Pass --issue for
# an issue number; otherwise it's treated as a PR.
#
# `move` and `assign` need the gh token's "project"/repo write scopes — this
# script's auth_check! tells you the exact fix if a call 403s on scope.

require_relative "herd_prs_lib"
include HerdPrs

def usage!
  warn <<~USAGE
    Usage:
      herd_prs_apply.rb move <owner/repo> <number> <StatusName> [--issue]
      herd_prs_apply.rb add <owner/repo> <number> <StatusName> [--issue]
      herd_prs_apply.rb assign <owner/repo> <number> <login> [--issue]
      herd_prs_apply.rb comment <owner/repo> <number>   (body piped via stdin)
      herd_prs_apply.rb sync-branch <owner/repo> <number>
  USAGE
  exit 1
end

def move(owner_repo, number, status_name, issue: false)
  option_id = STATUS_OPTIONS.fetch(status_name) do
    warn "Unknown status #{status_name.inspect}. Valid: #{STATUS_OPTIONS.keys.join(', ')}"
    exit 1
  end
  org, repo = owner_repo.split("/")
  item_id = project_item_id(org, repo, number, content_type: issue ? "issue" : "pullRequest")
  unless item_id
    warn "#{owner_repo}##{number} isn't on project #14 (Avdi's Desk)."
    exit 1
  end
  gh_graphql(<<~GQL)
    mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: "#{PROJECT_ID}"
        itemId: "#{item_id}"
        fieldId: "#{STATUS_FIELD_ID}"
        value: { singleSelectOptionId: "#{option_id}" }
      }) { projectV2Item { id } }
    }
  GQL
  puts "Moved #{owner_repo}##{number} -> #{status_name}"
end

# Puts a PR or issue onto project #14 for the first time and sets its status
# in one call. `move` can't do this — it only updates an item that's already
# there. Content node id comes straight from the repo, not from an existing
# project item (there isn't one yet).
def add(owner_repo, number, status_name, issue: false)
  option_id = STATUS_OPTIONS.fetch(status_name) do
    warn "Unknown status #{status_name.inspect}. Valid: #{STATUS_OPTIONS.keys.join(', ')}"
    exit 1
  end
  org, repo = owner_repo.split("/")
  content_field = issue ? "issue" : "pullRequest"
  lookup = gh_graphql(<<~GQL)
    query {
      repository(owner: "#{org}", name: "#{repo}") {
        #{content_field}(number: #{number}) { id }
      }
    }
  GQL
  content_id = lookup.dig("data", "repository", content_field, "id")
  unless content_id
    warn "#{owner_repo}##{number}: couldn't resolve a node id (wrong number, or wrong --issue/PR kind?)."
    exit 1
  end

  added = gh_graphql(<<~GQL)
    mutation {
      addProjectV2ItemById(input: {
        projectId: "#{PROJECT_ID}"
        contentId: "#{content_id}"
      }) { item { id } }
    }
  GQL
  item_id = added.dig("data", "addProjectV2ItemById", "item", "id")
  unless item_id
    warn "#{owner_repo}##{number}: addProjectV2ItemById failed -- #{added.inspect}"
    exit 1
  end

  gh_graphql(<<~GQL)
    mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: "#{PROJECT_ID}"
        itemId: "#{item_id}"
        fieldId: "#{STATUS_FIELD_ID}"
        value: { singleSelectOptionId: "#{option_id}" }
      }) { projectV2Item { id } }
    }
  GQL
  puts "Added #{owner_repo}##{number} -> #{status_name}"
end

def assign(owner_repo, number, login, issue: false)
  kind = issue ? "issue" : "pr"
  gh("#{kind}", "edit", number.to_s, "--repo", owner_repo, "--add-assignee", login)
  puts "Assigned #{login} to #{owner_repo}##{number}"
end

def comment(owner_repo, number, body)
  gh("pr", "comment", number.to_s, "--repo", owner_repo, "--body", body)
end

# Tries the cheap path first (GitHub's "Update branch" API — merges base into
# head with no local checkout). Only fails when there's a REAL content
# conflict, in which case it prints the worktree-based fallback recipe rather
# than attempting anything itself — conflict resolution needs a human/agent
# to read both sides, not a script guessing.
def sync_branch(owner_repo, number)
  org, repo = owner_repo.split("/")
  _stdout, stderr, status = Open3.capture3(
    GH_ENV, "gh", "api", "-X", "PUT", "repos/#{org}/#{repo}/pulls/#{number}/update-branch"
  )
  if status.success?
    puts "#{owner_repo}##{number}: merged cleanly, no conflict."
    return
  end
  if stderr.include?("merge conflict")
    branch = gh("pr", "view", number.to_s, "--repo", owner_repo, "--json", "headRefName",
      "-q", ".headRefName").strip
    warn <<~MSG
      #{owner_repo}##{number}: REAL conflict with base, needs manual resolution.
      Branch: #{branch}

        wt list | grep #{branch.split('/').last}   # find or create its worktree
        # EnterWorktree(path: <that path>)
        git fetch origin main && git merge origin/main --no-edit
        # resolve conflicts by hand — read both sides, don't blind-pick a side
        git add <resolved files> && git commit --no-edit && git push
    MSG
    exit 1
  end
  warn stderr
  exit 1
end

command = ARGV.shift
usage! unless command

case command
when "move"
  issue = ARGV.delete("--issue")
  owner_repo, number, status_name = ARGV
  usage! unless owner_repo && number && status_name
  auth_check!("project")
  move(owner_repo, number.to_i, status_name, issue: !!issue)
when "add"
  issue = ARGV.delete("--issue")
  owner_repo, number, status_name = ARGV
  usage! unless owner_repo && number && status_name
  auth_check!("project")
  add(owner_repo, number.to_i, status_name, issue: !!issue)
when "assign"
  issue = ARGV.delete("--issue")
  owner_repo, number, login = ARGV
  usage! unless owner_repo && number && login
  assign(owner_repo, number.to_i, login, issue: !!issue)
when "comment"
  owner_repo, number = ARGV
  usage! unless owner_repo && number
  comment(owner_repo, number.to_i, $stdin.read)
when "sync-branch"
  owner_repo, number = ARGV
  usage! unless owner_repo && number
  sync_branch(owner_repo, number.to_i)
else
  usage!
end
