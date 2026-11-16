BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE discount_type AS ENUM ('PERCENT', 'FIXED_AMOUNT', 'SPECIAL_PRICE', 'FREE_ITEM', 'OTHER');

CREATE TABLE search_places (
    place_id       uuid                   PRIMARY KEY,
    place_name     varchar(200)           NOT NULL,
    city           varchar(100)           NOT NULL,
    address_line   varchar(300)           NOT NULL,
    location       geography(Point, 4326) NOT NULL,
    category_code  varchar(50)            NOT NULL,
    category_name  varchar(100)           NOT NULL,
    timezone       varchar(64)            NOT NULL,
    search_vector  tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('pg_catalog.russian'::regconfig, place_name), 'A')
        || setweight(to_tsvector('pg_catalog.russian'::regconfig, address_line), 'B')
    ) STORED NOT NULL,

    CONSTRAINT search_places_name_not_blank CHECK (btrim(place_name) <> ''),
    CONSTRAINT search_places_city_not_blank CHECK (btrim(city) <> ''),
    CONSTRAINT search_places_address_not_blank CHECK (btrim(address_line) <> ''),
    CONSTRAINT search_places_timezone_format CHECK (timezone ~ '^[A-Za-z]+(/[A-Za-z0-9_+-]+)+$' OR timezone = 'UTC'),
    CONSTRAINT search_places_category_code_format CHECK (category_code ~ '^[a-z][a-z0-9_]*$')
);

CREATE INDEX search_places_search_vector_gin ON search_places USING gin (search_vector);
CREATE INDEX search_places_location_gist ON search_places USING gist (location);

CREATE TABLE search_offers (
    offer_id         uuid          PRIMARY KEY,
    place_id         uuid          NOT NULL REFERENCES search_places (place_id),
    discount_type    discount_type NOT NULL DEFAULT 'OTHER',
    discount_value   numeric(10, 2),
    last_verified_at timestamptz   NOT NULL,
    valid_from       date,
    valid_until      date,
    schedule_preview jsonb         NOT NULL DEFAULT '[]'::jsonb,

    CONSTRAINT search_offers_discount_value_range CHECK (
        discount_value IS NULL
        OR (discount_type = 'PERCENT' AND discount_value > 0 AND discount_value <= 100)
        OR (discount_type IN ('FIXED_AMOUNT', 'SPECIAL_PRICE') AND discount_value > 0)
    ),
    CONSTRAINT search_offers_validity_range CHECK (
        valid_from IS NULL OR valid_until IS NULL OR valid_until >= valid_from
    ),
    CONSTRAINT search_offers_schedule_is_array CHECK (jsonb_typeof(schedule_preview) = 'array')
);

CREATE INDEX search_offers_place_idx ON search_offers (place_id);

CREATE TABLE search_sync_state (
    entity_type varchar(10) NOT NULL,
    entity_id   uuid        NOT NULL,
    revision    int         NOT NULL,
    is_deleted  boolean     NOT NULL,
    applied_at  timestamptz NOT NULL,
    PRIMARY KEY (entity_type, entity_id),
    CONSTRAINT search_sync_state_entity_type CHECK (entity_type IN ('PLACE', 'OFFER')),
    CONSTRAINT search_sync_state_revision_nonnegative CHECK (revision >= 0)
);

COMMIT;
