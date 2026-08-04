#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetches every item in a 410Labs GitHub Projects (v2) board column, resolves
# Issue-tracked items to their linked PR(s), and batch-fetches CI/review/
# assignee data for every resulting PR in as few GraphQL round trips as
# possible. Prints one JSON object to stdout; nothing else goes to stdout.
#
# Usage:
#   herd_prs.rb [--org 410Labs] [--project 14] [--status Review] [--repo mailstrom]
#
# Requires: gh CLI, authenticated, with the read:project scope (this script
# checks and tells you the exact fix if it's missing — see auth_check!).

require "optparse"
require "time"
require_relative "herd_prs_lib"
include HerdPrs

options = {org: "410Labs", project: 14, status: "Review", repo: "mailstrom"}
OptionParser.new do |opts|
  opts.on("--org ORG") { |v| options[:org] = v }
  opts.on("--project N", Integer) { |v| options[:project] = v }
  opts.on("--status STATUS") { |v| options[:status] = v }
  opts.on("--repo REPO") { |v| options[:repo] = v }
end.parse!

def paginated_project_items(org, project)
  items = []
  cursor = "null"
  loop do
    query = <<~GQL
      query {
        organization(login: "#{org}") {
          projectV2(number: #{project}) {
            items(first: 100, after: #{cursor}) {
              pageInfo { hasNextPage endCursor }
              nodes {
                content {
                  __typename
                  ... on PullRequest {
                    number title url state isDraft
                    repository { name }
                    assignees(first: 10) { nodes { login } }
                  }
                  ... on Issue {
                    number title url state
                    repository { name }
                    assignees(first: 10) { nodes { login } }
                    closedByPullRequestsReferences(first: 10) {
                      nodes {
                        number title url state isDraft
                        repository { name }
                        assignees(first: 10) { nodes { login } }
                      }
                    }
                  }
                }
                fieldValueByName(name: "Status") {
                  ... on ProjectV2ItemFieldSingleSelectValue { name }
                }
              }
            }
          }
        }
      }
    GQL
    result = gh_graphql(query)
    if result["errors"]
      warn result["errors"].map { |e| e["message"] }.join("\n")
      exit 1
    end
    page = result.dig("data", "organization", "projectV2", "items")
    items.concat(page["nodes"])
    break unless page["pageInfo"]["hasNextPage"]

    cursor = page["pageInfo"]["endCursor"].to_json
  end
  items
end

def resolve_board_items(raw_items, status)
  raw_items
    .select { |item| item.dig("fieldValueByName", "name") == status }
    .map do |item|
      content = item["content"] || {}
      case content["__typename"]
      when "PullRequest"
        {kind: "direct_pr", repo: content.dig("repository", "name"), number: content["number"],
         title: content["title"], url: content["url"],
         assignees: content.dig("assignees", "nodes").to_a.map { |n| n["login"] }}
      when "Issue"
        linked = content.dig("closedByPullRequestsReferences", "nodes").to_a.map do |pr|
          {repo: pr.dig("repository", "name"), number: pr["number"], title: pr["title"],
           url: pr["url"], draft: pr["isDraft"],
           assignees: pr.dig("assignees", "nodes").to_a.map { |n| n["login"] }}
        end
        {kind: "issue", repo: content.dig("repository", "name"), number: content["number"],
         title: content["title"], url: content["url"],
         assignees: content.dig("assignees", "nodes").to_a.map { |n| n["login"] },
         linked_prs: linked}
      else
        {kind: "unknown_or_deleted"}
      end
    end
end

def batch_fetch_pr_details(repo, org, pr_numbers)
  return {} if pr_numbers.empty?

  aliases = pr_numbers.map do |n|
    <<~GQL
      pr#{n}: pullRequest(number: #{n}) {
        number title isDraft baseRefName additions deletions changedFiles updatedAt
        mergeable mergeStateStatus reviewDecision
        commits(last: 1) { nodes { commit { statusCheckRollup { state } committedDate } } }
        reviews(last: 30) { nodes { author { login } state submittedAt } }
        reviewThreads(first: 50) { nodes { isResolved } }
        comments(last: 20) { nodes { author { login } body createdAt } }
      }
    GQL
  end.join("\n")

  query = "query { repository(owner: \"#{org}\", name: \"#{repo}\") {\n#{aliases}\n} }"
  gh_graphql(query).dig("data", "repository")
end

# Deterministic classification from the rules Avdi gave for the "Avdi's Desk"
# board:
#   - CONFLICTING with base           -> needs a merge/rebase (independent of column)
#   - CI red                          -> needs manual real-vs-flaky triage (not auto-suggested)
#   - approved, no unresolved threads -> Ready
#   - approved, unresolved threads    -> Working (Avdi still addresses non-blocking notes)
#   - changes requested, addressed    -> re-review (back to/stays in Review)
#   - changes requested, unaddressed  -> Working
#   - never reviewed, CI green        -> fresh, ready as-is
# "Verification" (looks worked-on + local audits addressed, no QA report yet)
# is a heuristic off comment bodies — confirm by actually reading the
# comments before trusting it, don't move a column on this alone.
def classify(details)
  return {status: "missing"} unless details

  ci_state = details.dig("commits", "nodes", 0, "commit", "statusCheckRollup", "state")
  last_commit = details.dig("commits", "nodes", 0, "commit", "committedDate")
  reviews = details["reviews"]["nodes"]
  unresolved_threads = details.dig("reviewThreads", "nodes").to_a.count { |t| !t["isResolved"] }
  comments = details.dig("comments", "nodes").to_a
  has_qa_report = comments.any? { |c| c["body"].to_s.include?("QA report") }
  has_audit_verdict = comments.any? { |c| c["body"].to_s =~ /Blocking.*Should-fix|self-review|audit/i }
  base = {ci_state: ci_state, unresolved_threads: unresolved_threads,
          has_qa_report: has_qa_report, has_audit_verdict_comment: has_audit_verdict}

  return base.merge(status: "conflicting") if details["mergeable"] == "CONFLICTING"
  return base.merge(status: "ci_failing") if ci_state == "FAILURE"
  return base.merge(status: "draft") if details["isDraft"]

  committed_after_review = ->(last_review_at) {
    last_commit && last_review_at && Time.parse(last_commit) > Time.parse(last_review_at)
  }

  case details["reviewDecision"]
  when "APPROVED"
    base.merge(status: unresolved_threads.zero? ? "ready" : "unaddressed_feedback")
  when "CHANGES_REQUESTED"
    last_review_at = reviews.select { |r| r["state"] == "CHANGES_REQUESTED" }.map { |r| r["submittedAt"] }.max
    base.merge(status: committed_after_review.call(last_review_at) ? "re_review" : "unaddressed_feedback")
  else
    if reviews.empty? && unresolved_threads.zero?
      base.merge(status: "fresh", updated_at: details["updatedAt"])
    else
      last_review_at = reviews.map { |r| r["submittedAt"] }.max
      base.merge(status: committed_after_review.call(last_review_at) ? "re_review" : "unaddressed_feedback")
    end
  end
end

auth_check!("read:project")

raw_items = paginated_project_items(options[:org], options[:project])
board_items = resolve_board_items(raw_items, options[:status])

direct_prs = board_items.select { |i| i[:kind] == "direct_pr" }
issues_with_pr = board_items.select { |i| i[:kind] == "issue" && !i[:linked_prs].empty? }
issues_without_pr = board_items.select { |i| i[:kind] == "issue" && i[:linked_prs].empty? }

# Only PRs actually in the target repo get CI/review-checked; a PR living in
# another repo would need its own batch query (rare on this board, so it's
# just reported separately rather than silently skipped).
all_pr_refs = direct_prs + issues_with_pr.flat_map { |i| i[:linked_prs] }
same_repo_prs = all_pr_refs.select { |pr| pr[:repo] == options[:repo] }
other_repo_prs = all_pr_refs.reject { |pr| pr[:repo] == options[:repo] }

pr_details = batch_fetch_pr_details(options[:repo], options[:org], same_repo_prs.map { |pr| pr[:number] })

results = same_repo_prs.map do |pr|
  details = pr_details["pr#{pr[:number]}"]
  pr.merge(classification: classify(details), raw: details)
end

puts JSON.pretty_generate(
  org: options[:org], project: options[:project], status: options[:status],
  total_board_items_in_status: board_items.length,
  direct_pr_count: direct_prs.length,
  issue_with_linked_pr_count: issues_with_pr.length,
  issues_without_pr: issues_without_pr.map { |i| i.slice(:repo, :number, :title, :url, :assignees) },
  other_repo_prs: other_repo_prs,
  prs: results
)
