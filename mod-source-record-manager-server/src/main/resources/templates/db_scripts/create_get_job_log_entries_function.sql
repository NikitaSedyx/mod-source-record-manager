-- Script to create function to determine processed entities status based on performed actions and occurred errors number.
CREATE OR REPLACE FUNCTION get_entity_status(actions text[], errorsNumber bigint) RETURNS text AS $$
DECLARE status text;
BEGIN
    SELECT
        CASE WHEN errorsNumber != 0 THEN 'DISCARDED'
             WHEN array_length(actions, 1) > 0 THEN
                CASE actions[1]
                    WHEN 'CREATE' THEN 'CREATED'
                    WHEN 'UPDATE' THEN 'UPDATED'
                    WHEN 'NON_MATCH' THEN 'DISCARDED'
                END
        END
    INTO status;

    RETURN status;
END;
$$ LANGUAGE plpgsql;

-- Request to delete the old version of get_job_log_entries with a different return format.
DROP FUNCTION IF EXISTS get_job_log_entries(uuid,text,text,bigint,bigint);

-- Request to delete get_job_log_entries with a different return format.
DROP FUNCTION IF EXISTS get_job_log_entries(uuid,text,text,bigint,bigint,boolean,text);

-- Script to create function to get data import job log entries (jobLogEntry).
CREATE OR REPLACE FUNCTION get_job_log_entries(jobExecutionId uuid, sortingField text, sortingDir text, limitVal bigint, offsetVal bigint, errorsOnly boolean, entityType text)
  RETURNS TABLE(job_execution_id uuid, incoming_record_id uuid, source_id uuid, source_record_order integer, invoiceline_number text, title text,
                source_record_action_status text, source_entity_error text, source_record_tenant_id text,instance_action_status text, instance_entity_id text, instance_entity_hrid text, instance_entity_error text,
                instance_entity_tenant_id text, holdings_action_status text, holdings_entity_id text, holdings_entity_hrid text, holdings_permanent_location_id text,
                holdings_entity_error text, item_action_status text, item_entity_id text, item_entity_hrid text, item_entity_error text, item_holdings_id text, authority_action_status text,
                authority_entity_id text, authority_entity_error text, po_line_action_status text, po_line_entity_id text, po_line_entity_hrid text, po_line_entity_error text,
                order_entity_id text, invoice_action_status text, invoice_entity_id text[], invoice_entity_hrid text[], invoice_entity_error text, invoice_line_action_status text,
                invoice_line_entity_id text, invoice_line_entity_hrid text, invoice_line_entity_error text, total_count bigint,
                invoice_line_journal_record_id uuid, source_record_entity_type text, source_record_order_array integer[])
AS $$

DECLARE
  v_sortingField text DEFAULT sortingfield;
  v_entityAttribute text[] DEFAULT ARRAY[upper(entityType)];
BEGIN
  -- Using the source_record_order column in the array type provides support for sorting invoices and marc records.
  IF sortingField = 'source_record_order' THEN
    v_sortingField := 'source_record_order_array';
  END IF;

  IF entityType = 'MARC' THEN
    v_entityAttribute := ARRAY['MARC_BIBLIOGRAPHIC', 'MARC_HOLDINGS', 'MARC_AUTHORITY'];
  END IF;

  RETURN QUERY EXECUTE format('
WITH
  temp_result AS (
    SELECT id, job_execution_id, source_id, entity_type, entity_id, entity_hrid,
           CASE
             WHEN error_max != '''' OR action_type = ''NON_MATCH'' THEN ''DISCARDED''
             WHEN action_type = ''CREATE'' THEN ''CREATED''
             WHEN action_type IN (''UPDATE'', ''MODIFY'') THEN ''UPDATED''
             END AS action_type,
           action_status, action_date, source_record_order, error, title, tenant_id, instance_id, holdings_id, order_id, permanent_location_id
    FROM journal_records
           INNER JOIN (
      SELECT entity_type as entity_type_max, entity_id as entity_id_max, action_status as action_status_max, max(error) AS error_max,
             (array_agg(id ORDER BY array_position(array[''CREATE'', ''UPDATE'', ''MODIFY'', ''NON_MATCH''], action_type)))[1] AS id_max
      FROM journal_records
      WHERE job_execution_id = ''%1$s'' AND entity_type NOT IN (''EDIFACT'', ''INVOICE'')
      GROUP BY entity_type, entity_id, action_status, source_id, source_record_order
    ) AS action_type_by_source ON journal_records.id = action_type_by_source.id_max
  ),
  instances AS (
    SELECT action_type, entity_id, source_id, entity_hrid, error, job_execution_id, title, source_record_order, tenant_id
    FROM temp_result WHERE entity_type = ''INSTANCE''
  ),
  holdings AS (
    SELECT action_type, entity_id, entity_hrid, error, instance_id, permanent_location_id, temp_result.job_execution_id, temp_result.source_id, temp_result.title, temp_result.source_record_order
    FROM temp_result WHERE entity_type = ''HOLDINGS''
  ),
  items AS (
    SELECT action_type, entity_id, holdings_id, entity_hrid, error, instance_id, temp_result.job_execution_id, temp_result.source_id, temp_result.title, temp_result.source_record_order
    FROM temp_result WHERE entity_type = ''ITEM''
  ),
  po_lines AS (
    SELECT action_type,entity_id,entity_hrid,temp_result.source_id,error,order_id,temp_result.job_execution_id,temp_result.title,temp_result.source_record_order
    FROM temp_result WHERE entity_type = ''PO_LINE''
  ),
  authorities AS (
    SELECT action_type, entity_id, temp_result.source_id, error, temp_result.job_execution_id, temp_result.title, temp_result.source_record_order
    FROM temp_result WHERE entity_type = ''AUTHORITY''
  ),
  marc_authority AS (
    SELECT temp_result.job_execution_id, entity_id, title, source_record_order, action_type, error, source_id, tenant_id
    FROM temp_result WHERE entity_type = ''MARC_AUTHORITY''
  ),
  marc_holdings AS (
    SELECT temp_result.job_execution_id, entity_id, title, source_record_order, action_type, error, source_id, tenant_id
    FROM temp_result WHERE entity_type = ''MARC_HOLDINGS''
  )

SELECT records_actions.job_execution_id AS job_execution_id,
       records_actions.source_id AS source_id,
       records_actions.source_id AS incoming_record_id,
       records_actions.source_record_order AS source_record_order,
       '''' as invoiceline_number,
       coalesce(rec_titles.title, marc_holdings_info.title) AS title,
       CASE
         WHEN marc_errors_number != 0 OR marc_actions[array_length(marc_actions, 1)] = ''NON_MATCH'' THEN ''DISCARDED''
         WHEN marc_actions[array_length(marc_actions, 1)] = ''CREATE'' THEN ''CREATED''
         WHEN marc_actions[array_length(marc_actions, 1)] IN (''UPDATE'', ''MODIFY'') THEN ''UPDATED''
         END AS source_record_action_status,
       null AS source_entity_error,
       null AS source_record_tenant_id,
       instance_info.action_type AS instance_action_status,
       instance_info.instance_entity_id AS instance_entity_id,
       instance_info.instance_entity_hrid AS instance_entity_hrid,
       instance_info.instance_entity_error AS instance_entity_error,
       instance_info.instance_entity_tenant_id AS instance_entity_tenant_id,
       holdings_info.action_type AS holdings_action_status,
       holdings_info.holdings_entity_id AS holdings_entity_id,
       holdings_info.holdings_entity_hrid AS holdings_entity_hrid,
       holdings_info.holdings_permanent_location_id AS holdings_permanent_location_id,
       holdings_info.holdings_entity_error AS holdings_entity_error,
       items_info.action_type AS item_action_status,
       items_info.items_entity_id AS item_entity_id,
       items_info.items_entity_hrid AS item_entity_hrid,
       items_info.items_entity_error AS item_entity_error,
       items_info.item_holdings_id AS item_holdings_id,
       authority_info.action_type AS authority_action_status,
       coalesce(authority_info.authority_entity_id, marc_authority_info.marc_authority_entity_id) AS authority_entity_id,
       coalesce(authority_info.authority_entity_error, marc_authority_info.marc_authority_entity_error) AS authority_entity_error,
       po_lines_info.action_type AS po_line_action_status,
       po_lines_info.po_lines_entity_id AS po_lines_entity_id,
       po_lines_info.po_lines_entity_hrid AS po_lines_entity_hrid,
       po_lines_info.po_lines_entity_error AS po_lines_entity_error,
       null AS order_entity_id,
       null AS invoice_action_status,
       null::text[] AS invoice_entity_id,
       null::text[] AS invoice_entity_hrid,
       null AS invoice_entity_error,
       null AS invoice_line_action_status,
       null AS invoice_line_entity_id,
       null AS invoice_line_entity_hrid,
       null AS invoice_line_entity_error,
       records_actions.total_count,
       null::UUID AS invoice_line_journal_record_id,
       records_actions.source_record_entity_type,
       ARRAY[records_actions.source_record_order] AS source_record_order_array

FROM (
       SELECT journal_records.source_id, journal_records.source_record_order, journal_records.job_execution_id,
              array_agg(action_type ORDER BY array_position(array[''MATCH'', ''NON_MATCH'', ''MODIFY'', ''UPDATE'', ''CREATE''], action_type)) FILTER (WHERE entity_type IN (''MARC_BIBLIOGRAPHIC'', ''MARC_HOLDINGS'', ''MARC_AUTHORITY'')) AS marc_actions,
              count(journal_records.source_id) FILTER (WHERE (entity_type = ''MARC_BIBLIOGRAPHIC'' OR entity_type = ''MARC_HOLDINGS'' OR entity_type = ''MARC_AUTHORITY'') AND journal_records.error != '''') AS marc_errors_number,
              array_agg(action_type ORDER BY array_position(array[''CREATE'', ''MODIFY'', ''UPDATE'', ''NON_MATCH'', ''MATCH''], action_type)) FILTER (WHERE entity_type = ''INSTANCE'' AND (entity_id IS NOT NULL OR action_type = ''NON_MATCH'')) AS instance_actions,
              count(journal_records.source_id) FILTER (WHERE entity_type = ''INSTANCE'' AND journal_records.error != '''') AS instance_errors_number,
              array_agg(action_type ORDER BY array_position(array[''CREATE'', ''MODIFY'', ''UPDATE'', ''NON_MATCH''], action_type)) FILTER (WHERE entity_type = ''HOLDINGS'') AS holdings_actions,
              count(journal_records.source_id) FILTER (WHERE entity_type = ''HOLDINGS'' AND journal_records.error != '''') AS holdings_errors_number,
              array_agg(action_type ORDER BY array_position(array[''CREATE'', ''MODIFY'', ''UPDATE'', ''NON_MATCH''], action_type)) FILTER (WHERE entity_type = ''ITEM'') AS item_actions,
              count(journal_records.source_id) FILTER (WHERE entity_type = ''ITEM'' AND journal_records.error != '''') AS item_errors_number,
              array_agg(action_type ORDER BY array_position(array[''CREATE'', ''MODIFY'', ''UPDATE'', ''NON_MATCH''], action_type)) FILTER (WHERE entity_type = ''AUTHORITY'') AS authority_actions,
              count(journal_records.source_id) FILTER (WHERE entity_type = ''AUTHORITY'' AND journal_records.error != '''') AS authority_errors_number,
              array_agg(action_type ORDER BY array_position(array[''CREATE'', ''MODIFY'', ''UPDATE'', ''NON_MATCH''], action_type)) FILTER (WHERE entity_type = ''PO_LINE'') AS po_line_actions,
              count(journal_records.source_id) FILTER (WHERE entity_type = ''PO_LINE'' AND journal_records.error != '''') AS po_line_errors_number,
              count(journal_records.source_id) OVER () AS total_count,
              (array_agg(journal_records.entity_type) FILTER (WHERE entity_type IN (''MARC_BIBLIOGRAPHIC'', ''MARC_HOLDINGS'', ''MARC_AUTHORITY'')))[1] AS source_record_entity_type
       FROM journal_records
       WHERE journal_records.job_execution_id = ''%1$s'' and
           entity_type in (''MARC_BIBLIOGRAPHIC'', ''MARC_HOLDINGS'', ''MARC_AUTHORITY'', ''INSTANCE'', ''HOLDINGS'', ''ITEM'', ''AUTHORITY'', ''PO_LINE'')
       GROUP BY journal_records.source_id, journal_records.source_record_order, journal_records.job_execution_id
       HAVING count(journal_records.source_id) FILTER (WHERE (%3$L = ''ALL'' or entity_type = ANY(%4$L)) AND (NOT %2$L or journal_records.error <> '''')) > 0
     ) AS records_actions
       LEFT JOIN (SELECT journal_records.source_id, journal_records.title
                  FROM journal_records
                  WHERE journal_records.job_execution_id = ''%1$s'') AS rec_titles
                 ON rec_titles.source_id = records_actions.source_id AND rec_titles.title IS NOT NULL
       LEFT JOIN (
  SELECT   instances.action_type AS action_type,
           instances.job_execution_id AS job_execution_id,
           instances.title AS title,
           instances.source_id AS source_id,
           instances.entity_id AS instance_entity_id,
           instances.entity_hrid AS instance_entity_hrid,
           instances.error AS instance_entity_error,
           instances.tenant_id AS instance_entity_tenant_id
  FROM   instances
) AS instance_info ON instance_info.source_id = records_actions.source_id


       LEFT JOIN (
  SELECT
         holdings.action_type AS action_type,
         holdings.source_id AS source_id,
         holdings.title AS title,
         holdings.entity_id AS holdings_entity_id,
         holdings.entity_hrid AS holdings_entity_hrid,
         holdings.permanent_location_id AS holdings_permanent_location_id,
         holdings.error AS holdings_entity_error
  FROM holdings
) AS holdings_info ON holdings_info.source_id = records_actions.source_id

       LEFT JOIN (
  SELECT items.action_type AS action_type,
         items.source_id AS source_id,
         items.title AS title,
         items.entity_id AS items_entity_id,
         items.entity_hrid AS items_entity_hrid,
         items.error AS items_entity_error,
         items.holdings_id AS item_holdings_id
  FROM items
) AS items_info ON items_info.source_id = records_actions.source_id

       LEFT JOIN (
  SELECT po_lines.action_type AS action_type,
         po_lines.source_id AS source_id,
         po_lines.title AS title,
         po_lines.entity_id AS po_lines_entity_id,
         po_lines.entity_hrid AS po_lines_entity_hrid,
         po_lines.error AS po_lines_entity_error
  FROM po_lines
) AS po_lines_info ON po_lines_info.source_id = records_actions.source_id


       LEFT JOIN (
  SELECT authorities.action_type AS action_type,
         authorities.source_id AS source_id,
         authorities.title AS title,
         authorities.entity_id AS authority_entity_id,
         authorities.error AS authority_entity_error
  FROM  authorities
) AS authority_info ON authority_info.source_id = records_actions.source_id

       LEFT JOIN (
  SELECT marc_authority.action_type AS action_type,
         marc_authority.source_id AS source_id,
         marc_authority.title AS title,
         marc_authority.entity_id AS marc_authority_entity_id,
         marc_authority.error AS marc_authority_entity_error
  FROM  marc_authority
) AS marc_authority_info ON marc_authority_info.source_id = records_actions.source_id

       LEFT JOIN (
  SELECT marc_holdings.action_type AS action_type,
         marc_holdings.source_id AS source_id,
         marc_holdings.title AS title,
         marc_holdings.entity_id AS marc_authority_entity_id,
         marc_holdings.error AS marc_authority_entity_error
  FROM  marc_holdings
) AS marc_holdings_info ON marc_holdings_info.source_id = records_actions.source_id

       LEFT JOIN (SELECT journal_records.source_id,
                         CASE
                           WHEN COUNT(*) = 1 THEN array_to_string(array_agg(journal_records.error), '', '')
                           ELSE ''['' || array_to_string(array_agg(journal_records.error), '', '') || '']''
                           END AS error
                  FROM journal_records
                  WHERE journal_records.job_execution_id = ''%1$s'' AND journal_records.error != '''' GROUP BY journal_records.source_id) AS rec_errors
                 ON rec_errors.source_id = records_actions.source_id



UNION

SELECT records_actions.job_execution_id AS job_execution_id,
       records_actions.source_id AS source_id,
       records_actions.source_id AS incoming_record_id,
       source_record_order AS source_record_order,
       entity_hrid as invoiceline_number,
       invoice_line_info.title AS title,
       CASE
         WHEN marc_errors_number != 0 OR marc_actions[array_length(marc_actions, 1)] = ''NON_MATCH'' THEN ''DISCARDED''
         WHEN marc_actions[array_length(marc_actions, 1)] = ''CREATE'' THEN ''CREATED''
         WHEN marc_actions[array_length(marc_actions, 1)] IN (''UPDATE'', ''MODIFY'') THEN ''UPDATED''
         END AS source_record_action_status,
       error as source_entity_error,
       null AS source_record_tenant_id,
       null AS instance_action_status,
       null AS instance_entity_id,
       null AS instance_entity_hrid,
       null AS instance_entity_error,
       null AS instance_entity_tenant_id,
       null AS holdings_action_status,
       null AS holdings_entity_id,
       null AS holdings_entity_hrid,
       null AS holdings_permanent_location_id,
       null AS holdings_entity_error,
       null AS item_action_status,
       null AS item_entity_id,
       null AS item_entity_hrid,
       null AS item_entity_error,
       null AS item_holdings_id,
       null AS authority_action_status,
       null AS authority_entity_id,
       null AS authority_entity_error,
       null AS po_line_action_status,
       null AS po_line_entity_id,
       null AS po_line_entity_hrid,
       null AS po_line_entity_error,
       null AS order_entity_id,
       get_entity_status(invoice_actions, invoice_errors_number) AS invoice_action_status,
       ARRAY[invoice_fields.invoice_entity_id::text] AS invoice_entity_id,
       ARRAY[invoice_fields.invoice_entity_hrid::text] AS invoice_entity_hrid,
       invoice_fields.invoice_entity_error AS invoice_entity_error,
       invoice_line_info.invoice_line_action_status AS invoice_line_action_status,
       invoice_line_info.invoice_line_entity_id AS invoice_line_entity_id,
       invoice_line_info.invoice_line_entity_hrid AS invoice_line_entity_hrid,
       invoice_line_info.invoice_line_entity_error AS invoice_line_entity_error,
       records_actions.total_count,
       invoiceLineJournalRecordId AS invoice_line_journal_record_id,
       records_actions.source_record_entity_type,
       CASE
         WHEN get_entity_status(invoice_actions, invoice_errors_number) IS NOT null THEN string_to_array(entity_hrid, ''-'')::int[]
         ELSE ARRAY[source_record_order]
         END AS source_record_order_array
FROM (
       SELECT journal_records.source_id, journal_records.job_execution_id, source_record_order, entity_hrid, title, error,
              array[]::varchar[] AS marc_actions,
              cast(0 as integer) AS marc_errors_number,
              array_agg(action_type) FILTER (WHERE entity_type = ''INVOICE'') AS invoice_actions,
              count(journal_records.source_id) FILTER (WHERE entity_type = ''INVOICE'' AND journal_records.error != '''') AS invoice_errors_number,
              count(journal_records.source_id) OVER () AS total_count,
              id AS invoiceLineJournalRecordId,
              (array_agg(entity_type) FILTER (WHERE entity_type IN (''EDIFACT'')))[1] AS source_record_entity_type
       FROM journal_records
       WHERE journal_records.job_execution_id = ''%1$s'' and entity_type = ''INVOICE'' and title != ''INVOICE''
       GROUP BY journal_records.source_id, journal_records.source_record_order, journal_records.job_execution_id,
                entity_hrid, title, error, id
       HAVING count(journal_records.source_id) FILTER (WHERE (%3$L IN (''ALL'', ''INVOICE'')) AND (NOT %2$L or journal_records.error <> '''')) > 0
     ) AS records_actions

       LEFT JOIN LATERAL (
  SELECT journal_records.source_id,
         max(id) FILTER (WHERE entity_type = ''INVOICE'' AND title = ''INVOICE'') AS invoice_entity_id,
         max(entity_hrid) FILTER (WHERE entity_type = ''INVOICE'' AND title = ''INVOICE'') AS invoice_entity_hrid,
         max(error) FILTER (WHERE entity_type = ''INVOICE'' AND error <> '''') AS invoice_entity_error
  FROM journal_records
  WHERE  journal_records.job_execution_id = ''%1$s'' AND (entity_type = ''INVOICE'' OR title = ''INVOICE'')
  GROUP BY journal_records.source_id
  ) AS invoice_fields ON records_actions.source_id = invoice_fields.source_id


       LEFT JOIN LATERAL (
  SELECT journal_records.source_id,
         journal_records.job_execution_id,
         journal_records.title,
         CASE WHEN journal_records.action_status = ''ERROR'' THEN ''DISCARDED''
              WHEN journal_records.action_type = ''CREATE'' THEN ''CREATED''
           END AS invoice_line_action_status,
         entity_hrid AS invoice_line_entity_hrid,
         entity_id AS invoice_line_entity_id,
         error AS invoice_line_entity_error
  FROM journal_records
  WHERE  journal_records.job_execution_id = ''%1$s'' AND journal_records.entity_type = ''INVOICE'' AND journal_records.title != ''INVOICE''
  ) AS invoice_line_info ON  records_actions.source_id = invoice_line_info.source_id AND records_actions.entity_hrid = invoice_line_info.invoice_line_entity_hrid

ORDER BY %5$I %6$s
LIMIT %7$s OFFSET %8$s;

',
                              jobExecutionId, errorsOnly, entityType, v_entityAttribute, v_sortingField, sortingDir, limitVal, offsetVal);
END;
$$ LANGUAGE plpgsql;
