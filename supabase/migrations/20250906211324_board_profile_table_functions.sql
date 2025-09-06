create table "public"."board_profile" (
    "id" text not null default 'MAIN_PROFILE'::text,
    "board_name_bn" text not null,
    "board_name_en" text not null,
    "address" jsonb not null,
    "primary_phone" text not null,
    "secondary_phone" text,
    "email" text not null,
    "website" text,
    "logo_url" text,
    "establishment_date" date not null,
    "chairman" jsonb not null,
    "secretary" jsonb not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
);


CREATE UNIQUE INDEX board_profile_pkey ON public.board_profile USING btree (id);

alter table "public"."board_profile" add constraint "board_profile_pkey" PRIMARY KEY using index "board_profile_pkey";

alter table "public"."board_profile" add constraint "board_profile_id_check" CHECK ((id = 'MAIN_PROFILE'::text)) not valid;

alter table "public"."board_profile" validate constraint "board_profile_id_check";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.upsert_board_profile(p_profile_data jsonb)
 RETURNS board_profile
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_upserted_profile board_profile%ROWTYPE;
    v_user_role TEXT;
    v_current_user_id UUID;

    -- Variables to extract from JSONB
    _board_name_bn TEXT;
    _board_name_en TEXT;
    _address JSONB;
    _primary_phone TEXT;
    _secondary_phone TEXT;
    _email TEXT;
    _website TEXT;
    _logo_url TEXT;
    _establishment_date DATE;
    _chairman JSONB;
    _secretary JSONB;
BEGIN
    v_current_user_id := auth.uid();
    SELECT role INTO v_user_role FROM public.user_profiles WHERE id = v_current_user_id;

    IF NOT (v_user_role = 'admin' OR v_user_role = 'super_admin') THEN
        RAISE EXCEPTION 'প্রোফাইল আপডেট করার অনুমতি আপনার নেই।' USING ERRCODE = '42501';
    END IF;

    -- Extract and validate required fields from p_profile_data
    _board_name_bn := p_profile_data->>'board_name_bn';
    IF _board_name_bn IS NULL OR TRIM(_board_name_bn) = '' THEN RAISE EXCEPTION 'বোর্ডের বাংলা নাম আবশ্যক।'; END IF;

    _board_name_en := p_profile_data->>'board_name_en';
    IF _board_name_en IS NULL OR TRIM(_board_name_en) = '' THEN RAISE EXCEPTION 'বোর্ডের ইংরেজি নাম আবশ্যক।'; END IF;

    _address := p_profile_data->'address';
    IF _address IS NULL OR 
       _address->>'village_area' IS NULL OR TRIM(_address->>'village_area') = '' OR
       _address->>'post_office' IS NULL OR TRIM(_address->>'post_office') = '' OR
       _address->>'upazila' IS NULL OR TRIM(_address->>'upazila') = '' OR
       _address->>'district' IS NULL OR TRIM(_address->>'district') = '' OR
       _address->>'division' IS NULL OR TRIM(_address->>'division') = '' THEN
        RAISE EXCEPTION 'ঠিকানার সকল অংশ (গ্রাম/এলাকা, পোস্ট অফিস, উপজেলা, জেলা, বিভাগ) আবশ্যক।';
    END IF;

    _primary_phone := p_profile_data->>'primary_phone';
    IF _primary_phone IS NULL OR TRIM(_primary_phone) = '' THEN RAISE EXCEPTION 'প্রাথমিক ফোন নম্বর আবশ্যক।'; END IF;
    IF NOT (_primary_phone ~ '^(?:\+?88)?01[3-9]\d{8}$') THEN RAISE EXCEPTION 'প্রাথমিক ফোন নম্বরটি সঠিক নয়।'; END IF;

    _secondary_phone := p_profile_data->>'secondary_phone';
    IF _secondary_phone IS NOT NULL AND _secondary_phone <> '' AND NOT (_secondary_phone ~ '^(?:\+?88)?01[3-9]\d{8}$') THEN RAISE EXCEPTION 'দ্বিতীয় ফোন নম্বরটি সঠিক নয়।'; END IF;

    _email := p_profile_data->>'email';
    IF _email IS NULL OR TRIM(_email) = '' THEN RAISE EXCEPTION 'ইমেইল আবশ্যক।'; END IF;
    IF NOT (_email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$') THEN RAISE EXCEPTION 'সঠিক ইমেইল ফরম্যাট দিন।'; END IF;

    _website := p_profile_data->>'website';
     IF _website IS NOT NULL AND _website <> '' AND NOT (_website ~ '^https?:\/\/.+\..+') THEN RAISE EXCEPTION 'সঠিক ওয়েবসাইট ইউআরএল দিন (http:// or https://)'; END IF;


    _establishment_date := (p_profile_data->>'establishment_date')::DATE;
    IF _establishment_date IS NULL THEN RAISE EXCEPTION 'প্রতিষ্ঠা সাল আবশ্যক।'; END IF;

    _chairman := p_profile_data->'chairman';
    IF _chairman IS NULL OR _chairman->>'name' IS NULL OR TRIM(_chairman->>'name') = '' OR _chairman->>'mobile' IS NULL OR TRIM(_chairman->>'mobile') = '' THEN
        RAISE EXCEPTION 'চেয়ারম্যানের নাম ও মোবাইল নম্বর আবশ্যক।';
    END IF;
    IF NOT (_chairman->>'mobile' ~ '^(?:\+?88)?01[3-9]\d{8}$') THEN RAISE EXCEPTION 'চেয়ারম্যানের মোবাইল নম্বরটি সঠিক নয়।'; END IF;


    _secretary := p_profile_data->'secretary';
    IF _secretary IS NULL OR _secretary->>'name' IS NULL OR TRIM(_secretary->>'name') = '' OR _secretary->>'mobile' IS NULL OR TRIM(_secretary->>'mobile') = '' THEN
        RAISE EXCEPTION 'সচিবের নাম ও মোবাইল নম্বর আবশ্যক।';
    END IF;
     IF NOT (_secretary->>'mobile' ~ '^(?:\+?88)?01[3-9]\d{8}$') THEN RAISE EXCEPTION 'সচিবের মোবাইল নম্বরটি সঠিক নয়।'; END IF;

    _logo_url := p_profile_data->>'logo_url';


    INSERT INTO public.board_profile (
        id, board_name_bn, board_name_en, address,
        primary_phone, secondary_phone, email, website,
        logo_url, establishment_date, chairman, secretary,
        created_at, updated_at
    ) VALUES (
        'MAIN_PROFILE', _board_name_bn, _board_name_en, _address,
        _primary_phone, _secondary_phone, _email, _website,
        _logo_url, _establishment_date, _chairman, _secretary,
        NOW(), NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        board_name_bn = EXCLUDED.board_name_bn,
        board_name_en = EXCLUDED.board_name_en,
        address = EXCLUDED.address,
        primary_phone = EXCLUDED.primary_phone,
        secondary_phone = EXCLUDED.secondary_phone,
        email = EXCLUDED.email,
        website = EXCLUDED.website,
        logo_url = EXCLUDED.logo_url,
        establishment_date = EXCLUDED.establishment_date,
        chairman = EXCLUDED.chairman,
        secretary = EXCLUDED.secretary,
        updated_at = NOW() -- This will be handled by trigger if present, but explicit is fine.
    RETURNING * INTO v_upserted_profile;

    RETURN v_upserted_profile;
END;
$function$
;

grant delete on table "public"."board_profile" to "anon";

grant insert on table "public"."board_profile" to "anon";

grant references on table "public"."board_profile" to "anon";

grant select on table "public"."board_profile" to "anon";

grant trigger on table "public"."board_profile" to "anon";

grant truncate on table "public"."board_profile" to "anon";

grant update on table "public"."board_profile" to "anon";

grant delete on table "public"."board_profile" to "authenticated";

grant insert on table "public"."board_profile" to "authenticated";

grant references on table "public"."board_profile" to "authenticated";

grant select on table "public"."board_profile" to "authenticated";

grant trigger on table "public"."board_profile" to "authenticated";

grant truncate on table "public"."board_profile" to "authenticated";

grant update on table "public"."board_profile" to "authenticated";

grant delete on table "public"."board_profile" to "service_role";

grant insert on table "public"."board_profile" to "service_role";

grant references on table "public"."board_profile" to "service_role";

grant select on table "public"."board_profile" to "service_role";

grant trigger on table "public"."board_profile" to "service_role";

grant truncate on table "public"."board_profile" to "service_role";

grant update on table "public"."board_profile" to "service_role";


