# S3 and Confluence Ingress and Egress Data Flows

> [!WARNING]
> **AI-authored:** This change was autonomously planned and implemented by an AI software factory from a human-authored specification, with possible subsequent human review or modification.

Tests two directions of exchange: Markdown, JSON and VTT objects dropped in S3 `departures/` are published as Confluence pages under an arrivals page, and JSON code-macro pages under a Confluence departures page are exported to S3 and then deleted.

```sh
export ATLASSIAN_URL=... ATLASSIAN_EMAIL=... ATLASSIAN_API_TOKEN=... CONFLUENCE_SPACE=...
export CONFLUENCE_DEPARTURES_PAGE_ID=... CONFLUENCE_ARRIVALS_PAGE_ID=...
test/e2e/run.sh       # apply, then the VTT, JSON and Confluence-to-S3 cases
test/e2e/destroy.sh
```

## Notes

- A successful ingress deletes the source object. Markdown carries its own front matter, while raw JSON and VTT take `title` and `tags` from S3 object metadata. Tags become Confluence labels.
- `md2conf` turns a ` ```json ` fence into a code macro with `language=json`, but ` ```text ` becomes `language=none`.
- S3 to Confluence took about 10 s per object (Lambda ~6 s warm, 1.5 s init, 126 MB used). A Markdown object disappeared from S3 within 9 s.
- Each direct child of the departures page holds one JSON code macro. The CDATA becomes the S3 object body.
- Labels act as transit metadata: `path=e2e-json` sends the page to `e2e-json/<page-id>.json` (the default is `arrivals/<page-id>.json`). All labels also land in a `labels` metadata entry, joined with commas.
- Confluence to S3 took 265 s in the live run, because the exporter only runs on its `rate(5 minutes)` schedule.
- The exporter used to call `get_page_child_by_type(..., start=0, limit=100)`, which turns off the SDK's automatic pagination. It now reads every child before deleting any, so deletions cannot shift the page offsets mid-scan.
- In Confluence automation, `{{page.body.storage.substringBetween("<![CDATA[","]]>")}}` selects only the macro contents.
- In Confluence automation, `{{page.labels.name.match("environment=([^,]+)")}}` looks up a key-value label, and returns a comma-delimited list when several labels match.
