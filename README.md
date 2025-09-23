# cinema-management-sql
This project is created for learning how to design and manipulate a database
# 🎬 Cinema Booking System – DB Schema (Simplified)

> PostgreSQL, single-theater. Bỏ qua promotion/price policy để tập trung vào luồng “phòng – ghế – phim – suất – đặt vé – thanh toán – vé”.

## 📌 Nguyên tắc chung
- Thời gian dùng `TIMESTAMPTZ`.
- Giá dùng `NUMERIC(12,2)`.
- “Đóng băng” giá tại `booking_item.price` khi tạo đơn.
- **Chống oversell**: ở bản tối giản, ứng dụng phải bảo đảm không chèn trùng ghế cùng showtime. 

---

## 1) `screen`
Đại diện **phòng chiếu**.

**Thuộc tính**
- `screen_id BIGSERIAL` – **PK**
- `name TEXT NOT NULL UNIQUE`
- `seat_rows INT NOT NULL`
- `seat_cols INT NOT NULL`
- `is_active BOOLEAN NOT NULL DEFAULT TRUE`

**Ràng buộc**
- `UNIQUE (name)`

**Chỉ mục gợi ý**
- *(đã có UNIQUE trên name)*

**Quan hệ**
- 1 `screen` – N `seat`
- 1 `screen` – N `showtime`

---

## 2) `seat`
Đại diện **ghế cụ thể** trong một `screen`.

**Thuộc tính**
- `seat_id BIGSERIAL` – **PK**
- `screen_id BIGINT NOT NULL` → **FK** `screen(screen_id)`
- `row_label TEXT NOT NULL`  (ví dụ 'A', 'B'…)
- `col_number INT NOT NULL`  (1..N)
- `is_accessible BOOLEAN NOT NULL DEFAULT FALSE`
- `is_blocked BOOLEAN NOT NULL DEFAULT FALSE`

**Ràng buộc**
- `UNIQUE (screen_id, row_label, col_number)`

**Chỉ mục gợi ý**
- `CREATE INDEX idx_seat_screen ON seat(screen_id);`

**Quan hệ**
- N `seat` – 1 `screen`

---

## 3) `movie`
Thông tin **phim**.

**Thuộc tính**
- `movie_id BIGSERIAL` – **PK**
- `title TEXT NOT NULL`
- `duration_min INT NOT NULL`
- `rating TEXT` (tùy hệ thống: P/C13/C16…)
- `release_date DATE`
- `metadata JSONB` (poster, trailer, cast…)

**Ràng buộc**
- (tùy chọn) `CHECK (duration_min > 0)`

**Chỉ mục gợi ý**
- Tìm kiếm tiêu đề:  
  `CREATE INDEX idx_movie_title_trgm ON movie USING gin (title gin_trgm_ops);`

**Quan hệ**
- 1 `movie` – N `showtime`

---

## 4) `showtime`
Đại diện **suất chiếu cụ thể** (Movie X tại Screen Y, lúc Z).

**Thuộc tính**
- `showtime_id BIGSERIAL` – **PK**
- `movie_id BIGINT NOT NULL` → **FK** `movie(movie_id)`
- `screen_id BIGINT NOT NULL` → **FK** `screen(screen_id)`
- `start_time TIMESTAMPTZ NOT NULL`
- `end_time   TIMESTAMPTZ NOT NULL`
- `format_code TEXT` (ví dụ: '2D', '3D', 'IMAX') — *đơn giản hóa, không tách bảng*
- `audio_lang  TEXT` (ví dụ: 'vi', 'en')
- `subtitle_lang TEXT` (nullable)
- `base_price NUMERIC(12,2) NOT NULL`
- `status TEXT NOT NULL DEFAULT 'SCHEDULED'`  
  (giá trị gợi ý: `SCHEDULED|OPEN|CLOSED|CANCELLED`)

**Ràng buộc**
- `CHECK (end_time > start_time)`
- `UNIQUE (screen_id, start_time)`  — tránh trùng giờ bắt đầu trong cùng phòng  

**Chỉ mục gợi ý**
- `CREATE INDEX idx_showtime_screen_start ON showtime(screen_id, start_time);`
- `CREATE INDEX idx_showtime_movie_start ON showtime(movie_id, start_time);`

**Quan hệ**
- 1 `showtime` – 1 `movie`
- 1 `showtime` – 1 `screen`
- 1 `showtime` – N `booking`

---

## 5) `customer`
Thông tin **khách hàng**.

**Thuộc tính**
- `customer_id BIGSERIAL` – **PK**
- `full_name TEXT NOT NULL`
- `email CITEXT UNIQUE` (nullable, nếu cho phép chỉ số điện thoại)
- `phone TEXT`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

**Ràng buộc**
- `UNIQUE (email)` (nếu không cho phép null trùng lặp nhiều bản ghi)

**Chỉ mục gợi ý**
- `CREATE INDEX idx_customer_created ON customer(created_at);`

**Quan hệ**
- 1 `customer` – N `booking`

---

## 6) `booking`
Đại diện **giao dịch đặt vé** cho một `showtime`.

**Thuộc tính**
- `booking_id BIGSERIAL` – **PK**
- `customer_id BIGINT` → **FK** `customer(customer_id)` (nullable nếu cho phép guest)
- `showtime_id BIGINT NOT NULL` → **FK** `showtime(showtime_id)`
- `status TEXT NOT NULL DEFAULT 'PENDING'`  
  (giá trị gợi ý: `PENDING|PAID|CANCELLED|EXPIRED`)
- `hold_expires_at TIMESTAMPTZ` (hạn thanh toán/giữ chỗ)
- `total_amount NUMERIC(12,2) NOT NULL DEFAULT 0`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`

**Ràng buộc**
- (tùy chọn) trigger cập nhật `updated_at` khi detail đổi
- (tùy chọn) `CHECK (total_amount >= 0)`

**Chỉ mục gợi ý**
- `CREATE INDEX idx_booking_showtime_status ON booking(showtime_id, status);`
- `CREATE INDEX idx_booking_customer ON booking(customer_id);`

**Quan hệ**
- 1 `booking` – N `booking_item`
- 1 `booking` – N `payment`

---

## 7) `booking_item`
**Dòng chi tiết** của `booking` (mỗi hàng = 1 **ghế** trong showtime).

**Thuộc tính**
- `booking_item_id BIGSERIAL` – **PK**
- `booking_id BIGINT NOT NULL` → **FK** `booking(booking_id)`
- `seat_id BIGINT NOT NULL` → **FK** `seat(seat_id)`
- `price NUMERIC(12,2) NOT NULL`  — **đóng băng** tại thời điểm tạo
- *(tùy chọn)* `note TEXT`

**Ràng buộc**
- `UNIQUE (booking_id, seat_id)` — 1 booking không lặp cùng ghế
- *(Khuyến nghị nghiệp vụ)*: **Không cho phép cùng một `seat` xuất hiện ở 2 booking khác nhau cho cùng `showtime`**.  

**Chỉ mục gợi ý**
- `CREATE INDEX idx_bi_booking ON booking_item(booking_id);`
- `CREATE INDEX idx_bi_seat ON booking_item(seat_id);`

**Quan hệ**
- 1 `booking_item` – 1 `booking`
- 1 `booking_item` – 1 `seat`
- 1 `booking_item` – (tối đa) 1 `ticket`

---

## 8) `ticket`
**Vé** phát hành sau thanh toán thành công.

**Thuộc tính**
- `ticket_id BIGSERIAL` – **PK**
- `booking_item_id BIGINT NOT NULL UNIQUE` → **FK** `booking_item(booking_item_id)`
- `ticket_code TEXT NOT NULL UNIQUE`  (QR/Barcode)
- `issued_at TIMESTAMPTZ NOT NULL DEFAULT now()`
- `checked_in_at TIMESTAMPTZ` (nullable)

**Ràng buộc**
- `UNIQUE (booking_item_id)`
- `UNIQUE (ticket_code)`

**Chỉ mục gợi ý**
- `CREATE INDEX idx_ticket_checkedin ON ticket(checked_in_at);`

**Quan hệ**
- 1 `ticket` ↔ 1 `booking_item` (1–1)

---

## 9) `payment`
Thông tin **thanh toán** cho `booking`.

**Thuộc tính**
- `payment_id BIGSERIAL` – **PK**
- `booking_id BIGINT NOT NULL` → **FK** `booking(booking_id)`
- `provider TEXT NOT NULL`   (VNPay|MoMo|Stripe|Cash…)
- `method TEXT NOT NULL`     (CARD|WALLET|CASH…)
- `amount NUMERIC(12,2) NOT NULL`
- `currency TEXT NOT NULL DEFAULT 'VND'`
- `status TEXT NOT NULL`     (`INIT|SUCCESS|FAILED|REFUNDED`)
- `txn_ref TEXT`             (mã giao dịch cổng)
- `paid_at TIMESTAMPTZ`

**Ràng buộc**
- `CHECK (amount >= 0)`

**Chỉ mục gợi ý**
- `CREATE INDEX idx_payment_booking ON payment(booking_id);`
- `CREATE INDEX idx_payment_status ON payment(status);`

**Quan hệ**
- N `payment` – 1 `booking`

---

## 🗂️ Tóm tắt quan hệ chính
- `screen` **1–N** `seat`
- `movie` **N–N** `screen` qua `showtime`
- `showtime` **1–N** `booking`
- `customer` **1–N** `booking`
- `booking` **1–N** `booking_item`
- `booking` **N–N** `seat` qua `booking_item`
- `booking_item` **1–1** `ticket`
- `booking` **1–N** `payment`

---

