create table "public"."contact_submissions" (
    "id" uuid not null default gen_random_uuid(),
    "name" text not null,
    "email" text not null,
    "subject" text,
    "message" text not null,
    "status" text not null default 'new'::text,
    "created_at" timestamp with time zone not null default now()
);


alter table "public"."contact_submissions" enable row level security;

CREATE UNIQUE INDEX contact_submissions_pkey ON public.contact_submissions USING btree (id);

alter table "public"."contact_submissions" add constraint "contact_submissions_pkey" PRIMARY KEY using index "contact_submissions_pkey";

alter table "public"."contact_submissions" add constraint "contact_submissions_status_check" CHECK ((status = ANY (ARRAY['new'::text, 'read'::text, 'replied'::text, 'archived'::text]))) not valid;

alter table "public"."contact_submissions" validate constraint "contact_submissions_status_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.delete_contact_submission(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_role TEXT;
BEGIN
    SELECT role INTO v_user_role FROM public.user_profiles WHERE id = auth.uid();
    IF NOT (v_user_role = 'admin' OR v_user_role = 'super_admin') THEN
        RAISE EXCEPTION 'বার্তা মুছে ফেলার অনুমতি আপনার নেই।' USING ERRCODE = '42501';
    END IF;
    
    DELETE FROM public.contact_submissions WHERE id = p_id;
    
    IF NOT FOUND THEN
        RAISE WARNING 'প্রদত্ত আইডি (%) সহ কোনো বার্তা পাওয়া যায়নি।', p_id;
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_contact_submissions_list(p_page integer DEFAULT 1, p_limit integer DEFAULT 10, p_status_filter text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    _offset INTEGER;
    _items_jsonb JSONB;
    _total_items INTEGER;
    _where_clauses TEXT[] := ARRAY['TRUE'];
BEGIN
    _offset := (p_page - 1) * p_limit;

    IF p_status_filter IS NOT NULL AND p_status_filter <> '' THEN
        _where_clauses := array_append(_where_clauses, format('status = %L', p_status_filter));
    END IF;

    IF p_search_term IS NOT NULL AND TRIM(p_search_term) <> '' THEN
        _where_clauses := array_append(_where_clauses, format(
            '(name ILIKE %1$L OR email ILIKE %1$L OR subject ILIKE %1$L)',
            '%' || TRIM(p_search_term) || '%'
        ));
    END IF;

    -- Count query
    EXECUTE 'SELECT COUNT(*) FROM public.contact_submissions WHERE ' || array_to_string(_where_clauses, ' AND ')
    INTO _total_items;

    -- Data query
    EXECUTE '
        SELECT COALESCE(jsonb_agg(row_to_json(q)), ''[]''::jsonb) 
        FROM (
            SELECT id, name, email, subject, message, status, created_at
            FROM public.contact_submissions
            WHERE ' || array_to_string(_where_clauses, ' AND ') || '
            ORDER BY created_at DESC
            LIMIT ' || p_limit || ' OFFSET ' || _offset || '
        ) q'
    INTO _items_jsonb;

    RETURN jsonb_build_object('items', _items_jsonb, 'totalItems', _total_items);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_contact_submission_status(p_id uuid, p_new_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_role TEXT;
BEGIN
    SELECT role INTO v_user_role FROM public.user_profiles WHERE id = auth.uid();
    IF NOT (v_user_role = 'admin' OR v_user_role = 'super_admin') THEN
        RAISE EXCEPTION 'স্ট্যাটাস পরিবর্তনের অনুমতি আপনার নেই।' USING ERRCODE = '42501';
    END IF;

    IF NOT (p_new_status IN ('new', 'read', 'replied', 'archived')) THEN
        RAISE EXCEPTION 'অবৈধ স্ট্যাটাস।';
    END IF;
    
    UPDATE public.contact_submissions
    SET status = p_new_status
    WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE WARNING 'প্রদত্ত আইডি (%) সহ কোনো বার্তা পাওয়া যায়নি।', p_id;
    END IF;
END;
$function$
;

grant delete on table "public"."contact_submissions" to "anon";

grant insert on table "public"."contact_submissions" to "anon";

grant references on table "public"."contact_submissions" to "anon";

grant select on table "public"."contact_submissions" to "anon";

grant trigger on table "public"."contact_submissions" to "anon";

grant truncate on table "public"."contact_submissions" to "anon";

grant update on table "public"."contact_submissions" to "anon";

grant delete on table "public"."contact_submissions" to "authenticated";

grant insert on table "public"."contact_submissions" to "authenticated";

grant references on table "public"."contact_submissions" to "authenticated";

grant select on table "public"."contact_submissions" to "authenticated";

grant trigger on table "public"."contact_submissions" to "authenticated";

grant truncate on table "public"."contact_submissions" to "authenticated";

grant update on table "public"."contact_submissions" to "authenticated";

grant delete on table "public"."contact_submissions" to "service_role";

grant insert on table "public"."contact_submissions" to "service_role";

grant references on table "public"."contact_submissions" to "service_role";

grant select on table "public"."contact_submissions" to "service_role";

grant trigger on table "public"."contact_submissions" to "service_role";

grant truncate on table "public"."contact_submissions" to "service_role";

grant update on table "public"."contact_submissions" to "service_role";

create policy "Allow public insert for contact form submissions"
on "public"."contact_submissions"
as permissive
for insert
to anon, authenticated
with check (true);



