# Skew Check
### This is the ability to check skew for each schema when there are many objects (table, partition table, etc.) in a single database.
### last Existing functions take a long time to search for all objects and extract skew information, so they are extracted by schema as follows.

 skew check function by user define schema
 plz insert schema_name
 
 ex) select public.greenplum_check_skew('SCHEMA_NM');


## Skew Statistics Process
1) get greenplum_get_refilenodes             => public.greenplum_get_refilenodes
2) get segment_informations                  => public.greenplum_get_db_file_ext
3) get data file information each segment    => public.greenplum_get_file_statistics
4) generating skew report                    => public.greenplum_get_skew_report

## execute
SELECT * FROM public.greenplum_check_skew('public');

## data file information each segment ;

> SELECT * FROM public.greenplum_get_file_statistics ORDER BY 1,2

nspname|relation                 |segment_id|relfilenode|relkind|size     |
-------+-------------------------+----------+-----------+-------+---------+
public |greenplum_get_refilenodes|         0|105267     |r      |    65536|
public |greenplum_get_refilenodes|         2|114831     |r      |    65536|
public |greenplum_get_refilenodes|         3|114831     |r      |    65536|
public |greenplum_get_refilenodes|         1|105267     |r      |   131072|
public |sum_test                 |         2|114721     |r      |  2129920|
public |sum_test                 |         1|105157     |r      |  2129920|
public |sum_test                 |         3|114721     |r      |  2129920|
public |sum_test                 |         0|105157     |r      |  2129920|
public |t1                       |         2|57782      |r      |        0|
public |t1                       |         3|57782      |r      |        0|
public |t1                       |         0|51204      |r      |        0|
public |t1                       |         1|51204      |r      |        0|
public |tb_test1                 |         0|16864      |r      |        0|
public |tb_test1                 |         3|16864      |r      |        0|
public |tb_test1                 |         1|16864      |r      |    32768|
public |tb_test1                 |         2|16864      |r      |        0|
public |test                     |         3|114724     |r      |        0|
public |test                     |         0|105160     |r      |        0|
public |test                     |         2|114724     |r      |        0|
public |test                     |         1|105160     |r      |261160960|
public |test_random              |         2|114812     |r      | 63176704|
public |test_random              |         1|105248     |r      | 63111168|
public |test_random              |         0|105248     |r      | 63275008|
public |test_random              |         3|114812     |r      | 63209472|

24 row(s) fetched.

## skew Report ;

> select * FROM public.greenplum_get_skew_report

relation                        |vtotal_size_gb|vseg_min_size_gb|vseg_max_size_gb|vseg_avg_size_gb|vseg_gap_min_max_percent|vseg_gap_min_max_gb|vnb_empty_seg|
--------------------------------+--------------+----------------+----------------+----------------+------------------------+-------------------+-------------+
public.sum_test                 |          0.01|            0.00|            0.00|            0.00|                    0.00|               0.00|            0|
public.greenplum_get_refilenodes|          0.00|            0.00|            0.00|            0.00|                   50.00|               0.00|            0|
public.test                     |          0.24|            0.00|            0.24|            0.06|                  100.00|               0.24|            3|
public.test_random              |          0.24|            0.06|            0.06|            0.06|                    0.26|               0.00|            0|
public.t1                       |          0.00|            0.00|            0.00|            0.00|                    0.00|               0.00|            4|
public.tb_test1                 |          0.00|            0.00|            0.00|            0.00|                  100.00|               0.00|            3|

6 row(s) fetched.
