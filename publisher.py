import os
from pathlib import Path

import boto3
import frontmatter
from md2conf.api import ConfluenceAPI
from md2conf.environment import ConnectionProperties
from md2conf.options import ConfluencePageID, ProcessorOptions
from md2conf.publisher import Publisher


s3 = boto3.client("s3")
properties = ConnectionProperties(
    domain=os.environ["CONFLUENCE_URL"].removeprefix("https://"),
    base_path="/wiki/",
    space_key=os.environ["CONFLUENCE_SPACE_KEY"],
    user_name=os.environ["CONFLUENCE_EMAIL"],
    api_key=os.environ["CONFLUENCE_API_TOKEN"],
    api_version="v2",
)
options = ProcessorOptions(
    root_page=ConfluencePageID(os.environ["PARENT_PAGE_ID"]), generated_by=None
)


def handler(event, _context):
    bucket = event["detail"]["bucket"]["name"]
    key = event["detail"]["object"]["key"]
    obj = s3.get_object(Bucket=bucket, Key=key)
    source = obj["Body"].read().decode()
    extension = Path(key).suffix[1:]
    if extension != "md":
        language = {"json": "json", "vtt": "text"}[extension]
        source = frontmatter.dumps(
            frontmatter.Post(
                f"```{language}\n{source.rstrip()}\n```\n",
                title=obj["Metadata"]["title"],
                tags=obj["Metadata"]["tags"].split(","),
            )
        )

    path = Path("/tmp/page.md")
    path.write_text(source, encoding="utf-8")
    with ConfluenceAPI(properties) as api:
        Publisher(api, options).process(path)
    s3.delete_object(Bucket=bucket, Key=key)
