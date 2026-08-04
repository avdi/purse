# frozen_string_literal: true

# Shared plumbing for herd_prs.rb (read-only report) and herd_prs_apply.rb
# (mutating actions). Not meant to be run directly.

require "json"
require "open3"

module HerdPrs
  # gh picks up GH_TOKEN/GITHUB_TOKEN env vars over its own stored (and
  # possibly better-scoped) credential. That mismatch cost real time to
  # diagnose more than once — always strip them so `gh` uses its own auth.
  GH_ENV = {"GH_TOKEN" => nil, "GITHUB_TOKEN" => nil}.freeze

  PROJECT_ID = "PVT_kwDOAAk-UM4BSkwt"
  STATUS_FIELD_ID = "PVTSSF_lADOAAk-UM4BSkwtzhAEXJk"
  STATUS_OPTIONS = {
    "Inbox" => "f75ad846", "The Stack" => "47fc9ee4", "Working" => "a6e18b8d",
    "Verification" => "17d20488", "Review" => "0dcffbe6", "Ready" => "c664d3d9",
    "Circle Back" => "ca149ee3", "Done" => "98236657", "Rejected" => "785e6116",
  }.freeze

  module_function

  def gh_graphql(query)
    stdout, stderr, status = Open3.capture3(GH_ENV, "gh", "api", "graphql", "-f", "query=#{query}")
    unless status.success?
      warn stderr
      exit 1
    end
    result = JSON.parse(stdout)
    if result["errors"]
      warn result["errors"].map { |e| e["message"] }.join("\n")
      exit 1
    end
    result
  end

  def gh(*args)
    stdout, stderr, status = Open3.capture3(GH_ENV, "gh", *args)
    unless status.success?
      warn stderr
      exit 1
    end
    stdout
  end

  # `scope` is the OAuth scope this operation needs: "read:project" for board
  # reads, "project" (full read/write) for board mutations like moving a
  # column. They are granted independently by `gh auth refresh`.
  def auth_check!(scope)
    result = gh_graphql("query { viewer { login } }") rescue nil
    return if result && !result["errors"]

    warn <<~MSG
      gh token is missing the #{scope} scope.
      Fix (run yourself — needs an interactive browser/device-code prompt;
      unset GH_TOKEN/GITHUB_TOKEN first or `gh auth refresh` silently no-ops):

        env -u GH_TOKEN -u GITHUB_TOKEN gh auth refresh -h github.com -s #{scope}
    MSG
    exit 1
  end

  def project_item_id_for(org, repo, number, content_type)
    query = <<~GQL
      query {
        repository(owner: "#{org}", name: "#{repo}") {
          #{content_type}(number: #{number}) {
            projectItems(first: 10) { nodes { id project { number } } }
          }
        }
      }
    GQL
    result = gh_graphql(query)
    nodes = result.dig("data", "repository", content_type, "projectItems", "nodes") || []
    item = nodes.find { |n| n.dig("project", "number") == 14 }
    item && item["id"]
  end

  # The board sometimes tracks a PR directly, sometimes tracks the Issue it
  # closes (see "Why not just search PRs" in SKILL.md) — a caller working
  # from a PR number has no way to know which without checking. Try the PR
  # first; if it isn't itself a board item, follow its closingIssuesReferences
  # to find the tracking issue instead.
  #
  # Pass content_type: "issue" when `number` is an issue that has no PR at
  # all (e.g. the two no-linked-PR issues) — trying it as a PR first would
  # hard-error (GitHub's GraphQL raises on an unresolvable number, it
  # doesn't return null), not fall through gracefully. Auto-fallback only
  # covers "valid PR, tracked via its issue" (the common case); it can't
  # rescue a number that isn't a PR at all.
  def project_item_id(org, repo, number, content_type: "pullRequest")
    return project_item_id_for(org, repo, number, "issue") if content_type == "issue"

    direct = project_item_id_for(org, repo, number, "pullRequest")
    return direct if direct

    query = <<~GQL
      query {
        repository(owner: "#{org}", name: "#{repo}") {
          pullRequest(number: #{number}) {
            closingIssuesReferences(first: 5) { nodes { number } }
          }
        }
      }
    GQL
    issue_numbers = gh_graphql(query)
      .dig("data", "repository", "pullRequest", "closingIssuesReferences", "nodes")
      .to_a.map { |n| n["number"] }
    issue_numbers.each do |issue_number|
      found = project_item_id_for(org, repo, issue_number, "issue")
      return found if found
    end
    nil
  end
end
