#!/usr/bin/env python3

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


INSTANCE = os.environ.get("KOHA_INSTANCE", "INSTANCE")
DEFAULT_BORROWER = 55
ENV_FILE = Path(f"/etc/koha/sites/{INSTANCE}/research-api.env")

WOS_ENDPOINT = (
    "https://api.clarivate.com/apis/wos-starter/v1/documents"
)


def log(message: str = "") -> None:
    print(message, flush=True)


def run_mysql(
    sql: str,
    *,
    batch: bool = False,
    check: bool = True,
) -> str:
    command = ["koha-mysql", INSTANCE]

    if batch:
        command.extend(["-N", "-B"])

    command.extend(["-e", sql])

    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )

    if check and result.returncode != 0:
        raise RuntimeError(
            "MySQL command failed:\n"
            f"{result.stderr.strip()}\n"
            f"SQL:\n{sql}"
        )

    return result.stdout


def load_environment(path: Path) -> None:
    if not path.is_file():
        raise RuntimeError(f"Environment file missing: {path}")

    for raw_line in path.read_text(
        encoding="utf-8",
        errors="replace",
    ).splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in {"'", '"'}
        ):
            value = value[1:-1]

        if key:
            os.environ.setdefault(key, value)


def normalize_doi(value: Any) -> str:
    text = str(value or "").strip().lower()
    text = re.sub(r"^https?://(?:dx\.)?doi\.org/", "", text)
    text = re.sub(r"^doi:\s*", "", text)
    return text.strip().rstrip(".,; ")


def normalize_title(value: Any) -> str:
    text = str(value or "").lower()
    text = re.sub(r"&[a-z]+;", " ", text)
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def clean_text(value: Any) -> str:
    if value is None:
        return ""

    if isinstance(value, (dict, list)):
        return ""

    return re.sub(r"\s+", " ", str(value)).strip()


def recursive_values(
    node: Any,
    wanted_keys: set[str],
) -> list[Any]:
    found: list[Any] = []

    if isinstance(node, dict):
        for key, value in node.items():
            if key.lower() in wanted_keys:
                if isinstance(value, list):
                    found.extend(value)
                else:
                    found.append(value)

            found.extend(recursive_values(value, wanted_keys))

    elif isinstance(node, list):
        for item in node:
            found.extend(recursive_values(item, wanted_keys))

    return found


def first_recursive(
    node: Any,
    keys: list[str],
) -> str:
    values = recursive_values(
        node,
        {key.lower() for key in keys},
    )

    for value in values:
        cleaned = clean_text(value)

        if cleaned:
            return cleaned

    return ""


def extract_doi(hit: dict[str, Any]) -> str:
    identifiers = hit.get("identifiers")

    if isinstance(identifiers, dict):
        for key, value in identifiers.items():
            if key.lower() == "doi":
                if isinstance(value, list):
                    for item in value:
                        doi = normalize_doi(item)

                        if doi:
                            return doi
                else:
                    doi = normalize_doi(value)

                    if doi:
                        return doi

    return normalize_doi(
        first_recursive(hit, ["doi"])
    )


def extract_uid(hit: dict[str, Any]) -> str:
    uid = first_recursive(
        hit,
        ["uid", "ut"],
    )

    if not uid:
        possible_id = hit.get("id")

        if isinstance(possible_id, str):
            uid = possible_id

    uid = clean_text(uid).upper()

    if uid and not uid.startswith("WOS:"):
        if re.match(r"^[A-Z0-9]+$", uid):
            uid = f"WOS:{uid}"

    return uid


def extract_title(hit: dict[str, Any]) -> str:
    direct_title = hit.get("title")

    if isinstance(direct_title, str) and direct_title.strip():
        return clean_text(direct_title)

    return first_recursive(
        hit,
        [
            "documentTitle",
            "document-title",
            "itemTitle",
            "title",
        ],
    )


def extract_journal(hit: dict[str, Any]) -> str:
    source = hit.get("source")

    if isinstance(source, dict):
        for key in [
            "sourceTitle",
            "source_title",
            "title",
            "journal",
        ]:
            value = source.get(key)

            if isinstance(value, str) and value.strip():
                return clean_text(value)

    return first_recursive(
        hit,
        [
            "sourceTitle",
            "source_title",
            "journalTitle",
            "journal",
        ],
    )


def extract_document_type(hit: dict[str, Any]) -> str:
    return first_recursive(
        hit,
        [
            "documentType",
            "document_type",
            "doctype",
            "type",
        ],
    )


def extract_year(hit: dict[str, Any]) -> int | None:
    values = recursive_values(
        hit,
        {
            "publicationyear",
            "publishedyear",
            "pubyear",
            "year",
        },
    )

    for value in values:
        match = re.search(r"\b(19|20)\d{2}\b", clean_text(value))

        if match:
            year = int(match.group(0))

            if 1900 <= year <= datetime.date.today().year + 1:
                return year

    date_text = extract_date_text(hit)

    if date_text:
        match = re.match(r"^(\d{4})", date_text)

        if match:
            return int(match.group(1))

    return None


def extract_date_text(hit: dict[str, Any]) -> str:
    values = recursive_values(
        hit,
        {
            "publicationdate",
            "coverdate",
            "published",
            "date",
        },
    )

    for value in values:
        text = clean_text(value)

        if re.match(r"^\d{4}-\d{2}-\d{2}$", text):
            return text

        match = re.match(r"^(\d{4})-(\d{2})$", text)

        if match:
            return f"{match.group(1)}-{match.group(2)}-01"

        match = re.match(r"^(\d{4})$", text)

        if match:
            return f"{match.group(1)}-01-01"

    return ""


def extract_citation_count(hit: dict[str, Any]) -> int | None:
    candidates = recursive_values(
        hit,
        {
            "citations",
            "citationcount",
            "timescited",
            "times_cited",
        },
    )

    for value in candidates:
        if isinstance(value, bool):
            continue

        if isinstance(value, (int, float)):
            return max(0, int(value))

        text = clean_text(value)

        if text.isdigit():
            return int(text)

    return None


def sql_hex(value: str | None) -> str:
    if value is None:
        return "NULL"

    encoded = value.encode("utf-8").hex()
    return f"CONVERT(0x{encoded} USING utf8mb4)"


def sql_int(value: int | None) -> str:
    return "NULL" if value is None else str(int(value))


def fetch_wos(
    api_key: str,
    researcher_id: str,
) -> dict[str, Any]:
    page = 1
    limit = 50
    all_hits: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {}

    while True:
        query = urllib.parse.urlencode(
            {
                "db": "WOS",
                "q": f"AI={researcher_id}",
                "limit": limit,
                "page": page,
            }
        )

        request = urllib.request.Request(
            f"{WOS_ENDPOINT}?{query}",
            headers={
                "X-ApiKey": api_key,
                "Accept": "application/json",
                "User-Agent": (
                    "Koha-RIMS-WoS-Sync/1.0"
                ),
            },
        )

        try:
            with urllib.request.urlopen(
                request,
                timeout=120,
            ) as response:
                payload = json.load(response)
        except Exception as error:
            raise RuntimeError(
                f"WoS API request failed on page {page}: {error}"
            ) from error

        if page == 1:
            metadata = payload.get("metadata") or {}

        hits = payload.get("hits") or []

        if not isinstance(hits, list):
            raise RuntimeError("WoS API hits is not a list")

        valid_hits = [
            hit for hit in hits
            if isinstance(hit, dict)
        ]

        all_hits.extend(valid_hits)

        total_value = (
            metadata.get("total")
            or metadata.get("totalResults")
            or len(all_hits)
        )

        try:
            total = int(total_value)
        except (TypeError, ValueError):
            total = len(all_hits)

        log(
            f"WOS_PAGE={page} "
            f"HITS={len(valid_hits)} "
            f"ACCUMULATED={len(all_hits)} "
            f"TOTAL={total}"
        )

        if not hits or len(all_hits) >= total:
            break

        page += 1

        if page > 100:
            raise RuntimeError(
                "WoS pagination exceeded safety limit"
            )

    return {
        "metadata": metadata,
        "researcherId": researcher_id,
        "hits": all_hits,
    }


def get_researcher(borrower: int) -> dict[str, str]:
    output = run_mysql(
        f"""
        SELECT
            COALESCE(researcher_id, ''),
            COALESCE(orcid, ''),
            COALESCE(preferred_name, ''),
            COALESCE(official_name, '')
        FROM custom_profile_details
        WHERE borrowernumber = {borrower}
        LIMIT 1;
        """,
        batch=True,
    ).rstrip("\n")

    if not output:
        raise RuntimeError(
            f"Researcher profile missing for borrower {borrower}"
        )

    fields = output.split("\t")
    fields += [""] * (4 - len(fields))

    researcher_id, orcid, preferred_name, official_name = fields[:4]

    if not researcher_id.strip():
        raise RuntimeError(
            f"WoS Researcher ID missing for borrower {borrower}"
        )

    cache_name = run_mysql(
        f"""
        SELECT COALESCE(published_name, display_name, '')
        FROM researcher_author_identity_cache
        WHERE borrowernumber = {borrower}
          AND source_name = 'wos'
          AND CAST(source_author_id AS BINARY)
              = CAST({sql_hex(researcher_id.strip())} AS BINARY)
        LIMIT 1;
        """,
        batch=True,
    ).strip()

    author_name = (
        cache_name
        or official_name.strip()
        or preferred_name.strip()
    )

    return {
        "researcher_id": researcher_id.strip(),
        "orcid": orcid.strip(),
        "author_name": author_name,
    }


def load_master_rows() -> tuple[
    dict[str, int],
    dict[str, int],
]:
    output = run_mysql(
        """
        SELECT
            id,
            COALESCE(normalised_doi, ''),
            COALESCE(normalised_title, ''),
            COALESCE(title, '')
        FROM researcher_publications_master;
        """,
        batch=True,
    )

    doi_map: dict[str, int] = {}
    title_map: dict[str, int] = {}

    for line in output.splitlines():
        fields = line.split("\t", 3)
        fields += [""] * (4 - len(fields))

        publication_id = int(fields[0])
        doi = normalize_doi(fields[1])
        title = normalize_title(fields[2] or fields[3])

        if doi:
            doi_map.setdefault(doi, publication_id)

        if title:
            title_map.setdefault(title, publication_id)

    return doi_map, title_map


def build_sql(
    borrower: int,
    researcher_id: str,
    author_name: str,
    hits: list[dict[str, Any]],
) -> tuple[str, dict[str, int]]:
    doi_map, title_map = load_master_rows()

    existing_wos_output = run_mysql(
        """
        SELECT source_record_id, publication_id
        FROM researcher_publication_sources
        WHERE source_name = 'wos';
        """,
        batch=True,
    )

    wos_uid_map: dict[str, int] = {}

    for line in existing_wos_output.splitlines():
        fields = line.split("\t", 1)

        if len(fields) != 2:
            continue

        uid = clean_text(fields[0]).upper()

        if uid:
            wos_uid_map[uid] = int(fields[1])

    statements = [
        "SET NAMES utf8mb4;",
        "START TRANSACTION;",
    ]

    counters = {
        "api_records": 0,
        "new_master": 0,
        "doi_matched": 0,
        "title_matched": 0,
        "uid_matched": 0,
        "source_upserts": 0,
        "link_upserts": 0,
        "skipped_no_uid": 0,
        "skipped_no_title": 0,
    }

    temporary_id = -1

    for hit in hits:
        counters["api_records"] += 1

        uid = extract_uid(hit)
        doi = extract_doi(hit)
        title = extract_title(hit)
        normalized_title = normalize_title(title)

        if not uid:
            counters["skipped_no_uid"] += 1
            continue

        if not title:
            counters["skipped_no_title"] += 1
            continue

        existing_publication_id: int | None = None
        match_method = ""

        if uid in wos_uid_map:
            existing_publication_id = wos_uid_map[uid]
            match_method = "uid"
            counters["uid_matched"] += 1

        elif doi and doi in doi_map:
            existing_publication_id = doi_map[doi]
            match_method = "doi"
            counters["doi_matched"] += 1

        elif normalized_title and normalized_title in title_map:
            existing_publication_id = title_map[normalized_title]
            match_method = "title"
            counters["title_matched"] += 1

        journal = extract_journal(hit)
        publication_date = extract_date_text(hit)
        publication_year = extract_year(hit)
        document_type = extract_document_type(hit)
        citation_count = extract_citation_count(hit)

        raw_json = json.dumps(
            hit,
            ensure_ascii=False,
            separators=(",", ":"),
        )

        if existing_publication_id is None:
            publication_key = (
                f"doi:{doi}"
                if doi
                else f"wos:{uid.lower()}"
            )

            statements.append(
                """
                INSERT INTO researcher_publications_master
                (
                    publication_key,
                    doi,
                    normalised_doi,
                    title,
                    normalised_title,
                    journal,
                    publication_date,
                    publication_year,
                    document_type,
                    created_at,
                    updated_at
                )
                VALUES
                (
                    {publication_key},
                    {doi},
                    {normalised_doi},
                    {title},
                    {normalised_title},
                    {journal},
                    {publication_date},
                    {publication_year},
                    {document_type},
                    NOW(),
                    NOW()
                )
                ON DUPLICATE KEY UPDATE
                    id = LAST_INSERT_ID(id),
                    doi = COALESCE(
                        NULLIF(VALUES(doi), ''),
                        doi
                    ),
                    normalised_doi = COALESCE(
                        NULLIF(VALUES(normalised_doi), ''),
                        normalised_doi
                    ),
                    title = CASE
                        WHEN VALUES(title) <> ''
                        THEN VALUES(title)
                        ELSE title
                    END,
                    normalised_title = CASE
                        WHEN VALUES(normalised_title) <> ''
                        THEN VALUES(normalised_title)
                        ELSE normalised_title
                    END,
                    journal = COALESCE(
                        NULLIF(VALUES(journal), ''),
                        journal
                    ),
                    publication_date = COALESCE(
                        VALUES(publication_date),
                        publication_date
                    ),
                    publication_year = COALESCE(
                        VALUES(publication_year),
                        publication_year
                    ),
                    document_type = COALESCE(
                        NULLIF(VALUES(document_type), ''),
                        document_type
                    ),
                    updated_at = NOW();
                """.format(
                    publication_key=sql_hex(publication_key),
                    doi=sql_hex(doi) if doi else "NULL",
                    normalised_doi=(
                        sql_hex(doi) if doi else "NULL"
                    ),
                    title=sql_hex(title),
                    normalised_title=sql_hex(normalized_title),
                    journal=(
                        sql_hex(journal)
                        if journal else "NULL"
                    ),
                    publication_date=(
                        sql_hex(publication_date)
                        if publication_date else "NULL"
                    ),
                    publication_year=sql_int(publication_year),
                    document_type=(
                        sql_hex(document_type)
                        if document_type else "NULL"
                    ),
                )
            )

            statements.append(
                "SET @publication_id = LAST_INSERT_ID();"
            )

            temporary_id -= 1
            current_map_id = temporary_id

            if doi:
                doi_map[doi] = current_map_id

            if normalized_title:
                title_map[normalized_title] = current_map_id

            counters["new_master"] += 1

        else:
            statements.append(
                f"SET @publication_id = {existing_publication_id};"
            )

            statements.append(
                """
                UPDATE researcher_publications_master
                SET
                    doi = CASE
                        WHEN
                            (doi IS NULL OR TRIM(doi) = '')
                            AND {doi} IS NOT NULL
                        THEN {doi}
                        ELSE doi
                    END,
                    normalised_doi = CASE
                        WHEN
                            (
                                normalised_doi IS NULL
                                OR TRIM(normalised_doi) = ''
                            )
                            AND {normalised_doi} IS NOT NULL
                        THEN {normalised_doi}
                        ELSE normalised_doi
                    END,
                    journal = CASE
                        WHEN
                            (
                                journal IS NULL
                                OR TRIM(journal) = ''
                            )
                            AND {journal} IS NOT NULL
                        THEN {journal}
                        ELSE journal
                    END,
                    publication_date = COALESCE(
                        publication_date,
                        {publication_date}
                    ),
                    publication_year = COALESCE(
                        publication_year,
                        {publication_year}
                    ),
                    document_type = CASE
                        WHEN
                            (
                                document_type IS NULL
                                OR TRIM(document_type) = ''
                            )
                            AND {document_type} IS NOT NULL
                        THEN {document_type}
                        ELSE document_type
                    END,
                    updated_at = NOW()
                WHERE id = @publication_id;
                """.format(
                    doi=sql_hex(doi) if doi else "NULL",
                    normalised_doi=(
                        sql_hex(doi) if doi else "NULL"
                    ),
                    journal=(
                        sql_hex(journal)
                        if journal else "NULL"
                    ),
                    publication_date=(
                        sql_hex(publication_date)
                        if publication_date else "NULL"
                    ),
                    publication_year=sql_int(publication_year),
                    document_type=(
                        sql_hex(document_type)
                        if document_type else "NULL"
                    ),
                )
            )

        source_url = (
            "https://www.webofscience.com/wos/woscc/"
            f"full-record/{urllib.parse.quote(uid, safe=':')}"
        )

        statements.append(
            """
            INSERT INTO researcher_publication_sources
            (
                publication_id,
                source_name,
                source_record_id,
                source_url,
                citation_count,
                raw_json,
                first_seen_at,
                last_synced_at
            )
            VALUES
            (
                @publication_id,
                'wos',
                {uid},
                {source_url},
                {citation_count},
                {raw_json},
                NOW(),
                NOW()
            )
            ON DUPLICATE KEY UPDATE
                publication_id = VALUES(publication_id),
                source_url = VALUES(source_url),
                citation_count = COALESCE(
                    VALUES(citation_count),
                    citation_count
                ),
                raw_json = VALUES(raw_json),
                last_synced_at = NOW();
            """.format(
                uid=sql_hex(uid),
                source_url=sql_hex(source_url),
                citation_count=sql_int(citation_count),
                raw_json=sql_hex(raw_json),
            )
        )

        statements.append(
            """
            INSERT INTO researcher_publication_links
            (
                borrowernumber,
                publication_id,
                source_name,
                source_author_id,
                author_name,
                affiliation_status,
                match_score,
                system_decision,
                review_status,
                first_linked_at,
                last_confirmed_at
            )
            VALUES
            (
                {borrower},
                @publication_id,
                'wos',
                {researcher_id},
                {author_name},
                'confirmed',
                100.00,
                'confirmed',
                'system_confirmed',
                NOW(),
                NOW()
            )
            ON DUPLICATE KEY UPDATE
                source_author_id = VALUES(source_author_id),
                author_name = VALUES(author_name),
                affiliation_status = 'confirmed',
                match_score = 100.00,
                system_decision = 'confirmed',
                review_status = CASE
                    WHEN review_status IN
                    (
                        'approved',
                        'rejected',
                        'manually_reviewed'
                    )
                    THEN review_status
                    ELSE 'system_confirmed'
                END,
                last_confirmed_at = NOW();
            """.format(
                borrower=borrower,
                researcher_id=sql_hex(researcher_id),
                author_name=sql_hex(author_name),
            )
        )

        counters["source_upserts"] += 1
        counters["link_upserts"] += 1

        log(
            f"PREPARED uid={uid} "
            f"doi={doi or '-'} "
            f"match={match_method or 'new'} "
            f"title={title[:90]}"
        )

    statements.append("COMMIT;")

    return "\n".join(statements), counters


def execute_sql_file(sql_text: str) -> None:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix="bu-wos-publication-sync-",
        suffix=".sql",
        delete=False,
    ) as handle:
        handle.write(sql_text)
        sql_path = Path(handle.name)

    try:
        with sql_path.open("r", encoding="utf-8") as handle:
            result = subprocess.run(
                ["koha-mysql", INSTANCE],
                stdin=handle,
                text=True,
                capture_output=True,
                check=False,
            )

        if result.returncode != 0:
            raise RuntimeError(
                "WoS publication SQL transaction failed:\n"
                f"{result.stderr.strip()}\n"
                f"SQL file retained temporarily at: {sql_path}"
            )

    finally:
        if sql_path.exists():
            sql_path.unlink()


def verify(
    borrower: int,
    expected_records: int,
) -> None:
    output = run_mysql(
        f"""
        SELECT
            COUNT(*) AS link_rows,
            COUNT(DISTINCT rpl.publication_id)
                AS distinct_publications,
            SUM(rpl.system_decision = 'confirmed')
                AS confirmed_rows,
            SUM(
                rps.raw_json IS NOT NULL
                AND JSON_VALID(rps.raw_json) = 1
            ) AS valid_raw_json_rows
        FROM researcher_publication_links rpl
        INNER JOIN researcher_publication_sources rps
            ON rps.publication_id = rpl.publication_id
           AND rps.source_name = rpl.source_name
        WHERE rpl.borrowernumber = {borrower}
          AND rpl.source_name = 'wos';
        """,
        batch=True,
    ).strip()

    log()
    log("===== WOS DATABASE VERIFICATION =====")
    log(
        "link_rows\t"
        "distinct_publications\t"
        "confirmed_rows\t"
        "valid_raw_json_rows"
    )
    log(output)

    fields = output.split("\t") if output else []
    fields += ["0"] * (4 - len(fields))

    link_rows = int(fields[0] or 0)
    distinct_rows = int(fields[1] or 0)
    confirmed_rows = int(fields[2] or 0)
    valid_json_rows = int(fields[3] or 0)

    if distinct_rows != expected_records:
        raise RuntimeError(
            "Verification failed: "
            f"API records={expected_records}, "
            f"database WoS records={distinct_rows}"
        )

    if confirmed_rows != expected_records:
        raise RuntimeError(
            "Verification failed: not all WoS links are confirmed"
        )

    if valid_json_rows != expected_records:
        raise RuntimeError(
            "Verification failed: not all WoS raw JSON rows are valid"
        )

    if link_rows != expected_records:
        raise RuntimeError(
            "Verification failed: unexpected duplicate WoS links"
        )

    log("WOS_PUBLICATION_COUNTS_OK")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Identifier-bound Web of Science publication sync "
            "for Koha researcher profiles."
        )
    )

    parser.add_argument(
        "--borrower",
        type=int,
        default=DEFAULT_BORROWER,
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
    )

    arguments = parser.parse_args()

    load_environment(ENV_FILE)

    api_key = os.environ.get("WOS_API_KEY", "").strip()

    if not api_key:
        raise RuntimeError(
            f"WOS_API_KEY missing from {ENV_FILE}"
        )

    researcher = get_researcher(arguments.borrower)

    log("============================================================")
    log(" WOS IDENTIFIER-BOUND PUBLICATION SYNC")
    log("============================================================")
    log(f"Borrower:          {arguments.borrower}")
    log(f"WoS Researcher ID: {researcher['researcher_id']}")
    log(f"ORCID:             {researcher['orcid']}")
    log(f"Author name:       {researcher['author_name']}")
    log()

    payload = fetch_wos(
        api_key,
        researcher["researcher_id"],
    )

    hits = payload.get("hits") or []

    if not hits:
        raise RuntimeError(
            "WoS API returned zero publications; "
            "existing database data was not modified"
        )

    sql_text, counters = build_sql(
        arguments.borrower,
        researcher["researcher_id"],
        researcher["author_name"],
        hits,
    )

    log()
    log("===== PREPARED IMPORT SUMMARY =====")

    for key, value in counters.items():
        log(f"{key}={value}")

    if arguments.dry_run:
        log("DRY_RUN_OK")
        return 0

    execute_sql_file(sql_text)
    verify(arguments.borrower, len(hits))

    log()
    log("============================================================")
    log(" WOS_PUBLICATION_SYNC_OK")
    log("============================================================")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            f"ERROR: {error}",
            file=sys.stderr,
            flush=True,
        )
        raise SystemExit(1)
