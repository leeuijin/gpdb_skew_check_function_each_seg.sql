DROP FUNCTION IF EXISTS public.greenplum_check_skew(text);
CREATE FUNCTION public.greenplum_check_skew(v_schema_name text)
    RETURNS TABLE (
    	relation text,
    	vtotal_size_gb numeric,
    	vseg_min_size_gb numeric,
    	vseg_max_size_gb numeric,
    	vseg_avg_size_gb numeric,
    	vseg_gap_min_max_percent numeric,
    	vseg_gap_min_max_gb numeric,
    	vnb_empty_seg bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
	v_function_name text := 'greenplum_check_skew';
    v_location int;
    v_sql text;
    v_db_oid text;
BEGIN
    v_location := 1000;
    SET client_min_messages TO WARNING;

    -- Get the database oid
    v_location := 2000;
    SELECT d.oid INTO v_db_oid
    FROM pg_database d
    WHERE datname = current_database();

    -- Drop the temp table if it exists
    v_location := 3000;
    v_sql := 'DROP TABLE IF EXISTS public.greenplum_get_refilenodes CASCADE';
    v_location := 3100;
    EXECUTE v_sql;

    -- Temp table to temporary store the relfile records
    v_location := 4000;
    v_sql := 'CREATE TABLE public.greenplum_get_refilenodes ('
    '    segment_id int,'
    '    o oid,'
    '    relname name,'
    '    relnamespace oid,'
    '    relkind char,'
    '    relfilenode bigint'
    ')';
    v_location := 4100;
    EXECUTE v_sql;

    -- Store all the data related to the relfilenodes from all
    -- the segments into the temp table
    v_location := 5000;
    v_sql := 'INSERT INTO public.greenplum_get_refilenodes SELECT '
	'  s.gp_segment_id segment_id, '
	'  s.oid o, '
	'  s.relname, '
	'  s.relnamespace,'
	'  s.relkind,'
	'  s.relfilenode '
	'FROM '
	'  gp_dist_random(''pg_class'') s ' -- all segment
	'UNION '
	'  SELECT '
	'  m.gp_segment_id segment_id, '
	'  m.oid o, '
	'  m.relname, '
	'  m.relnamespace,'
	'  m.relkind,'
	'  m.relfilenode '
	'FROM '
	'  pg_class m ';  -- relfiles from master
	v_location := 5100;
    EXECUTE v_sql;

	-- Drop the external table if it exists
    v_location := 6000;
    v_sql := 'DROP EXTERNAL WEB TABLE IF EXISTS public.greenplum_get_db_file_ext';
    v_location := 6100;
    EXECUTE v_sql;

	-- Create a external that runs a shell script to extract all the files 
	-- on the base directory
	v_location := 7000;
    v_sql := 'CREATE EXTERNAL WEB TABLE public.greenplum_get_db_file_ext ' ||
            '(segment_id int, relfilenode text, filename text, ' ||
            'size numeric) ' ||
            'execute E''ls -l $GP_SEG_DATADIR/base/' || v_db_oid ||
            ' | ' ||
            'grep gpadmin | ' ||
            E'awk {''''print ENVIRON["GP_SEGMENT_ID"] "\\t" $9 "\\t" ' ||
            'ENVIRON["GP_SEG_DATADIR"] "/base/' || v_db_oid ||
            E'/" $9 "\\t" $5''''}'' on all ' || 'format ''text''';

    v_location := 7100;
    EXECUTE v_sql;


    -- Drop the datafile statistics view if exists
	v_location := 8000;
	v_sql := 'DROP VIEW IF EXISTS public.greenplum_get_file_statistics';
	v_location := 8100;
    EXECUTE v_sql;

    -- Create a view to get all the datafile statistics
    v_location := 9000;
	v_sql :='CREATE VIEW public.greenplum_get_file_statistics AS '
			'SELECT '
			'  n.nspname, '
			'  c.relname relation, '
			'  osf.segment_id, '
			'  split_part(osf.relfilenode, ''.'' :: text, 1) relfilenode, '
			'  c.relkind, '
			'  sum(osf.size) size '
			'FROM '
			'  public.greenplum_get_db_file_ext osf '
			'  JOIN public.greenplum_get_refilenodes c ON ('
			'    c.segment_id = osf.segment_id '
			'    AND split_part(osf.relfilenode, ''.'' :: text, 1) = c.relfilenode :: text'
			'  ) '
			'  JOIN pg_namespace n ON c.relnamespace = n.oid '
			'WHERE '
			'  osf.relfilenode ~ ''(\d+(?:\.\d+)?)'' '
		    '  AND c.relkind = ''r'' :: char '
			'  AND n.nspname not in ('
			'    ''pg_catalog'', '
			'    ''information_schema'', '
			'    ''gp_toolkit'' '
			'  ) '
			'  AND not n.nspname like ''pg_temp%'' '
		    '  AND not n.nspname like ''pg_toast%'' '
			'  AND n.nspname = ' || quote_literal(v_schema_name) || ' '
			'  GROUP BY 1,2,3,4,5';
	v_location := 9100;
    EXECUTE v_sql;

     -- Drop the skew report view view if exists
	v_location := 10000;
	v_sql := 'DROP VIEW IF EXISTS public.greenplum_get_skew_report';
	v_location := 10100;
    EXECUTE v_sql;

    -- Create a view to get all the table skew statistics
    v_location := 11100;
	v_sql :='CREATE VIEW public.greenplum_get_skew_report AS '
			'SELECT '
			'	sub.nspname || ''.'' || sub.relation AS relation,'
			'	(sum(sub.size)/(1024^3))::numeric(15,2) AS vtotal_size_GB,'  --Size on segments
			'    (min(sub.size)/(1024^3))::numeric(15,2) AS vseg_min_size_GB,'
			'    (max(sub.size)/(1024^3))::numeric(15,2) AS vseg_max_size_GB,'
			'    (avg(sub.size)/(1024^3))::numeric(15,2) AS vseg_avg_size_GB,' --Percentage of gap between smaller segment and bigger segment
			'    (100*(max(sub.size) - min(sub.size))/greatest(max(sub.size),1))::numeric(6,2) AS vseg_gap_min_max_percent,'
			'    ((max(sub.size) - min(sub.size))/(1024^3))::numeric(15,2) AS vseg_gap_min_max_GB,'
			'    count(sub.size) filter (where sub.size = 0) AS vnb_empty_seg '
			'FROM '
			'public.greenplum_get_file_statistics sub'
			'  GROUP BY 1';
	v_location := 11100;
    EXECUTE v_sql;

    -- Return the data back
    RETURN query (
        SELECT
            *
        FROM public.greenplum_get_skew_report a);

    -- Throw the exception whereever it encounters one
    EXCEPTION
        WHEN OTHERS THEN
                RAISE EXCEPTION '(%:%:%)', v_function_name, v_location, sqlerrm;
END;
$$;
