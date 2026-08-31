import os
import sys
import time
from pathlib import Path

from atlassian import Confluence


confluence = Confluence(
    url=os.environ["ATLASSIAN_URL"],
    username=os.environ["ATLASSIAN_EMAIL"],
    password=os.environ["ATLASSIAN_API_TOKEN"],
    cloud=True,
)


def children(parent_id):
    return confluence.get_page_child_by_type(parent_id)


def wait_page(parent_id, title, expected_text, expected_label, expected_language):
    for _ in range(60):
        matches = [page for page in children(parent_id) if page["title"] == title]
        if len(matches) == 1:
            page_id = str(matches[0]["id"])
            page = confluence.get_page_by_id(page_id, expand="body.storage")
            labels = {
                label["name"]
                for label in confluence.get_page_labels(page_id, limit=100)["results"]
            }
            storage = page["body"]["storage"]["value"]
            language = (
                f'<ac:parameter ac:name="language">{expected_language}</ac:parameter>'
            )
            if (
                expected_text in storage
                and expected_label in labels
                and language in storage
                and "<ac:plain-text-body><![CDATA[" in storage
            ):
                print(page_id)
                return
        time.sleep(3)
    raise RuntimeError(f"timed out waiting for {title}")


def create_json(title, path):
    source = Path(path).read_text()
    body = (
        '<ac:structured-macro ac:name="code" ac:schema-version="1">'
        '<ac:parameter ac:name="language">json</ac:parameter>'
        f"<ac:plain-text-body><![CDATA[{source}]]></ac:plain-text-body>"
        "</ac:structured-macro>"
    )
    page = confluence.create_page(
        os.environ["CONFLUENCE_SPACE"],
        title,
        body,
        parent_id=os.environ["CONFLUENCE_DEPARTURES_PAGE_ID"],
    )
    page_id = str(page["id"])
    for label in ("egress", "e2e", "path=e2e-json"):
        confluence.set_page_label(page_id, label)
    print(page_id)


def wait_deleted(page_id):
    for _ in range(60):
        if all(str(page["id"]) != page_id for page in children(os.environ["CONFLUENCE_DEPARTURES_PAGE_ID"])):
            return
        time.sleep(2)
    raise RuntimeError(f"page {page_id} was not deleted")


if sys.argv[1] == "wait-page":
    wait_page(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6])
elif sys.argv[1] == "create-json":
    create_json(sys.argv[2], sys.argv[3])
elif sys.argv[1] == "wait-deleted":
    wait_deleted(sys.argv[2])
