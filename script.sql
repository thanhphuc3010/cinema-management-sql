-- =========================================================
-- Cinema Booking System – Simplified Schema (PostgreSQL)
-- =========================================================

BEGIN;

-- 0) Extensions (khuyến nghị)
CREATE EXTENSION IF NOT EXISTS citext;
-- Dùng cho ràng buộc "không chồng giờ chiếu" nâng cao (tùy chọn):
-- CREATE EXTENSION IF NOT EXISTS btree_gist;

-- =========================================================
-- 1) SCREEN (phòng chiếu)
-- =========================================================
CREATE TABLE screen (
  screen_id   BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  seat_rows   INT  NOT NULL,
  seat_cols   INT  NOT NULL,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT uq_screen_name UNIQUE (name)
);

-- =========================================================
-- 2) SEAT (ghế trong phòng)
-- =========================================================
CREATE TABLE seat (
  seat_id       BIGSERIAL PRIMARY KEY,
  screen_id     BIGINT NOT NULL REFERENCES screen(screen_id) ON DELETE CASCADE,
  row_label     TEXT NOT NULL,
  col_number    INT  NOT NULL,
  is_accessible BOOLEAN NOT NULL DEFAULT FALSE,
  is_blocked    BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT uq_seat_pos UNIQUE (screen_id, row_label, col_number)
);
CREATE INDEX idx_seat_screen ON seat(screen_id);

-- =========================================================
-- 3) MOVIE (phim)
-- =========================================================
CREATE TABLE movie (
  movie_id      BIGSERIAL PRIMARY KEY,
  title         TEXT NOT NULL,
  duration_min  INT  NOT NULL,
  rating        TEXT,
  release_date  DATE,
  metadata      JSONB,
  CONSTRAINT ck_movie_duration_pos CHECK (duration_min > 0)
);
-- Tối ưu tìm kiếm theo tiêu đề (cần pg_trgm nếu dùng):
-- CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- CREATE INDEX idx_movie_title_trgm ON movie USING gin (title gin_trgm_ops);

-- =========================================================
-- 4) SHOWTIME (suất chiếu: Movie X @ Screen Y @ Time Z)
-- =========================================================
CREATE TABLE showtime (
  showtime_id    BIGSERIAL PRIMARY KEY,
  movie_id       BIGINT NOT NULL REFERENCES movie(movie_id),
  screen_id      BIGINT NOT NULL REFERENCES screen(screen_id),
  start_time     TIMESTAMPTZ NOT NULL,
  end_time       TIMESTAMPTZ NOT NULL,
  format_code    TEXT,              -- ví dụ '2D' | '3D' | 'IMAX' (đơn giản hoá)
  audio_lang     TEXT,              -- 'vi' | 'en' ...
  subtitle_lang  TEXT,              -- nullable
  base_price     NUMERIC(12,2) NOT NULL,
  status         TEXT NOT NULL DEFAULT 'SCHEDULED', -- SCHEDULED|OPEN|CLOSED|CANCELLED
  CONSTRAINT ck_showtime_time_order CHECK (end_time > start_time),
  -- Tránh trùng giờ bắt đầu trong cùng phòng (đủ tốt cho MVP):
  CONSTRAINT uq_showtime_screen_start UNIQUE (screen_id, start_time)
);
CREATE INDEX idx_showtime_screen_start ON showtime(screen_id, start_time);
CREATE INDEX idx_showtime_movie_start  ON showtime(movie_id, start_time);

-- Nếu muốn NGĂN CHỒNG GIỜ CHIẾU trong cùng screen (nâng cao), bỏ comment 3 dòng dưới:
-- ALTER TABLE showtime
--   ADD CONSTRAINT ex_showtime_no_overlap
--   EXCLUDE USING gist (screen_id WITH =, tsrange(start_time, end_time) WITH &&);

-- =========================================================
-- 5) CUSTOMER (khách hàng)
-- =========================================================
CREATE TABLE customer (
  customer_id BIGSERIAL PRIMARY KEY,
  full_name   TEXT   NOT NULL,
  email       CITEXT UNIQUE,
  phone       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_customer_created ON customer(created_at);

-- =========================================================
-- 6) BOOKING (đơn đặt vé cho 1 showtime)
-- =========================================================
CREATE TABLE booking (
  booking_id     BIGSERIAL PRIMARY KEY,
  customer_id    BIGINT REFERENCES customer(customer_id),
  showtime_id    BIGINT NOT NULL REFERENCES showtime(showtime_id),
  status         TEXT NOT NULL DEFAULT 'PENDING', -- PENDING|PAID|CANCELLED|EXPIRED
  hold_expires_at TIMESTAMPTZ,
  total_amount   NUMERIC(12,2) NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT ck_booking_total_nonneg CHECK (total_amount >= 0)
);
CREATE INDEX idx_booking_showtime_status ON booking(showtime_id, status);
CREATE INDEX idx_booking_customer        ON booking(customer_id);

-- =========================================================
-- 7) BOOKING_ITEM (chi tiết từng ghế của 1 booking)
--    -> bảng trung gian N–M giữa booking và seat
-- =========================================================
CREATE TABLE booking_item (
  booking_item_id BIGSERIAL PRIMARY KEY,
  booking_id      BIGINT NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
  seat_id         BIGINT NOT NULL REFERENCES seat(seat_id),
  price           NUMERIC(12,2) NOT NULL,
  -- Ghi chú: giá đã "đóng băng" tại thời điểm tạo booking_item
  CONSTRAINT uq_bi_booking_seat UNIQUE (booking_id, seat_id)
);
CREATE INDEX idx_bi_booking ON booking_item(booking_id);
CREATE INDEX idx_bi_seat    ON booking_item(seat_id);

-- **Nâng cao chống oversell (khuyến nghị nếu muốn ràng buộc tại DB):
-- 1) thêm cột showtime_id để enforce seat chỉ xuất hiện 1 lần trong 1 showtime:
-- ALTER TABLE booking_item ADD COLUMN showtime_id BIGINT;
-- ALTER TABLE booking_item
--   ADD CONSTRAINT fk_bi_showtime FOREIGN KEY (showtime_id) REFERENCES showtime(showtime_id);
-- ALTER TABLE booking_item
--   ADD CONSTRAINT uq_bi_showtime_seat UNIQUE (showtime_id, seat_id);
-- => Cần trigger BEFORE INSERT/UPDATE đảm bảo booking_item.showtime_id = booking.showtime_id.

-- =========================================================
-- 8) TICKET (vé phát hành sau khi thanh toán)
-- =========================================================
CREATE TABLE ticket (
  ticket_id       BIGSERIAL PRIMARY KEY,
  booking_item_id BIGINT NOT NULL UNIQUE REFERENCES booking_item(booking_item_id) ON DELETE CASCADE,
  ticket_code     TEXT   NOT NULL UNIQUE, -- QR/Barcode
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  checked_in_at   TIMESTAMPTZ
);
CREATE INDEX idx_ticket_checkedin ON ticket(checked_in_at);

-- =========================================================
-- 9) PAYMENT (thanh toán cho booking)
-- =========================================================
CREATE TABLE payment (
  payment_id BIGSERIAL PRIMARY KEY,
  booking_id BIGINT NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
  provider   TEXT   NOT NULL,             -- VNPay|MoMo|Stripe|Cashier...
  method     TEXT   NOT NULL,             -- CARD|WALLET|CASH...
  amount     NUMERIC(12,2) NOT NULL,
  currency   TEXT   NOT NULL DEFAULT 'VND',
  status     TEXT   NOT NULL,             -- INIT|SUCCESS|FAILED|REFUNDED
  txn_ref    TEXT,
  paid_at    TIMESTAMPTZ,
  CONSTRAINT ck_payment_amount_nonneg CHECK (amount >= 0)
);
CREATE INDEX idx_payment_booking ON payment(booking_id);
CREATE INDEX idx_payment_status  ON payment(status);

COMMIT;
