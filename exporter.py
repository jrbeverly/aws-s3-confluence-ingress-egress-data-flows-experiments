import json
import os

import boto3
from atlassian import Confluence


s3 = boto3.client("s3")
confluence = Confluence(
    url=os.environ["CONFLUENCE_URL"],
    username=os.environ["CONFLUENCE_EMAIL"],
    password=os.environ["CONFLUENCE_API_TOKEN"],
    cloud=True,
)


def handler(_event, _context):
    children = list(confluence.get_page_child_by_type(os.environ["PARENT_PAGE_ID"]))

    for child in children:
        page_id = str(child["id"])
        page = confluence.get_page_by_id(page_id, expand="body.storage")
        labels = sorted(
            label["name"]
            for label in confluence.get_page_labels(page_id, limit=100)["results"]
        )
        storage = page["body"]["storage"]["value"]
        document = json.loads(
            storage.partition("<![CDATA[")[2].partition("]]>")[0]
        )
        metadata = {"labels": ",".join(labels)}
        metadata.update(label.split("=", 1) for label in labels if "=" in label)
        s3.put_object(
            Bucket=os.environ["BUCKET_NAME"],
            Key=f"{metadata.get('path', 'arrivals').strip('/')}/{page_id}.json",
            Body=(json.dumps(document, indent=2) + "\n").encode(),
            ContentType="application/json",
            Metadata=metadata,
        )
        confluence.remove_page(page_id)
