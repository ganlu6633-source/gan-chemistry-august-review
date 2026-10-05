-- Run inside the candidate migration transaction, followed by ROLLBACK.
-- 1601 deliberately unknown identifiers exercise the real proof RPC boundary.
-- No fake questions, source reviews, bindings or learner answers are inserted.
do $batch_boundary$
declare sizes integer[]; proof_count integer; rejected boolean:=false;
begin
 with image_candidates as materialized (
  select 'QA-NOT-A-REGISTERED-ORIGINAL-'||n as id,
    ((row_number() over(order by n)-1)/800)::bigint as batch_number
  from generate_series(1,1601) n
 ), image_batches as materialized (
  select batch_number,array_agg(id order by id) as question_ids
  from image_candidates group by batch_number
 ) select array_agg(cardinality(question_ids) order by batch_number) into sizes from image_batches;
 if sizes<>array[800,800,1] then raise exception 'image proof batch boundary is incorrect: %',sizes; end if;
 with image_candidates as materialized (
  select 'QA-NOT-A-REGISTERED-ORIGINAL-'||n as id,
    ((row_number() over(order by n)-1)/800)::bigint as batch_number
  from generate_series(1,1601) n
 ), image_batches as materialized (
  select batch_number,array_agg(id order by id) as question_ids
  from image_candidates group by batch_number
 ) select count(*) into proof_count from image_batches batch
   cross join lateral public.chem_junior_image_question_context(batch.question_ids) proof;
 if proof_count<>0 then raise exception 'unknown identifiers received source proof'; end if;
 begin
  perform * from public.chem_junior_image_question_context(array(select 'QA-NOT-A-REGISTERED-ORIGINAL-'||n from generate_series(1,801) n));
 exception when raise_exception then
  if sqlerrm<>'invalid junior image context request' then raise; end if;
  rejected:=true;
 end;
 if not rejected then raise exception 'unbatched 801 identifiers were accepted'; end if;
end;
$batch_boundary$;
select 'PASS: real image proof RPC accepts three bounded batches (800/800/1), produces no unreviewed proof and rejects unbatched 801' as result;
