BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE search_offers (
    offer_id         uuid                   PRIMARY KEY,
    place_id         uuid                   NOT NULL,
    place_name       varchar(200)           NOT NULL,
    city             varchar(100)           NOT NULL,
    address_line     varchar(300)           NOT NULL,
    location         geography(Point, 4326) NOT NULL,
    category_code    varchar(50)            NOT NULL,
    category_name    varchar(100)           NOT NULL,
    discount_type    varchar(30)            NOT NULL,
    discount_value   numeric(10, 2),
    conditions       varchar(2000)          NOT NULL,
    last_verified_at timestamptz            NOT NULL,
    valid_from       date,
    valid_until      date,
    timezone         varchar(64)            NOT NULL,
    schedule_preview jsonb                  NOT NULL DEFAULT '[]'::jsonb,
    search_vector    tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('pg_catalog.russian'::regconfig, place_name), 'A')
        || setweight(to_tsvector('pg_catalog.russian'::regconfig, conditions), 'B')
        || setweight(to_tsvector('pg_catalog.russian'::regconfig, city || ' ' || address_line), 'C')
    ) STORED NOT NULL,

    CONSTRAINT search_offers_place_name_not_blank CHECK (btrim(place_name) <> ''),
    CONSTRAINT search_offers_city_not_blank CHECK (btrim(city) <> ''),
    CONSTRAINT search_offers_address_not_blank CHECK (btrim(address_line) <> ''),
    CONSTRAINT search_offers_category_name_not_blank CHECK (btrim(category_name) <> ''),
    CONSTRAINT search_offers_conditions_not_blank CHECK (btrim(conditions) <> ''),
    CONSTRAINT search_offers_timezone_not_blank CHECK (btrim(timezone) <> ''),
    CONSTRAINT search_offers_location_not_empty CHECK (NOT ST_IsEmpty(location::geometry)),
    CONSTRAINT search_offers_category_code_format CHECK (category_code ~ '^[a-z][a-z0-9_]*$'),
    CONSTRAINT search_offers_discount_type_allowed CHECK (
        discount_type IN ('PERCENT', 'FIXED_AMOUNT', 'SPECIAL_PRICE', 'FREE_ITEM', 'OTHER')
    ),
    CONSTRAINT search_offers_discount_value_range CHECK (
        CASE
            WHEN discount_type = 'PERCENT' THEN
                discount_value IS NOT NULL AND discount_value > 0 AND discount_value <= 100
            WHEN discount_type IN ('FIXED_AMOUNT', 'SPECIAL_PRICE') THEN
                discount_value IS NOT NULL AND discount_value > 0 AND discount_value <> 'NaN'::numeric
            ELSE discount_value IS NULL
        END
    ),
    CONSTRAINT search_offers_validity_range CHECK (
        valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from
    ),
    CONSTRAINT search_offers_schedule_is_array CHECK (jsonb_typeof(schedule_preview) = 'array')
);

CREATE INDEX search_offers_search_vector_gin ON search_offers USING gin (search_vector);
CREATE INDEX search_offers_location_gist ON search_offers USING gist (location);
CREATE INDEX search_offers_place_idx ON search_offers (place_id);
CREATE INDEX search_offers_city_idx ON search_offers (city);
CREATE INDEX search_offers_category_idx ON search_offers (category_code);

CREATE TABLE search_document_state (
    offer_id        uuid        PRIMARY KEY,
    search_revision int         NOT NULL,
    is_deleted      boolean     NOT NULL,
    applied_at      timestamptz NOT NULL,
    CONSTRAINT search_document_state_revision_nonnegative CHECK (search_revision >= 0)
);

COMMIT;
