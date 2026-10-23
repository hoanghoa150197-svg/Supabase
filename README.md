# Team Workspace v1.0

Website quản lý công việc theo mô hình **Dự án → Công việc → Nhân viên**, gồm tài khoản Admin và nhân viên, báo cáo tiến độ %, ghi chú, ngày báo cáo và file đính kèm. GitHub Pages chỉ lưu frontend; dữ liệu thật lưu tại Supabase.

## 1. Tạo Supabase

1. Đăng ký tại https://supabase.com, tạo project.
2. Vào **SQL Editor** → New query → dán toàn bộ `supabase/schema.sql` → Run. Dùng project mới; script tạo bảng, trigger, RLS và private Storage bucket.
3. Vào **Authentication → Users → Add user** tạo tài khoản Admin với email/mật khẩu; sao chép **UUID** của user vừa tạo.
4. Trong SQL Editor chạy (thay UUID/email/tên):

```sql
insert into public.profiles(id,email,full_name,role)
values ('UUID-ADMIN-CUA-BAN','admin@example.com','Quản trị viên','admin');
```

5. Vào **Project Settings → API** (hoặc Connect) lấy **Project URL** và **Publishable key** (hoặc legacy anon key). **Không bao giờ đưa service_role key vào frontend, GitHub hay tin nhắn.**
6. Vào **Authentication → URL Configuration**: thêm URL GitHub Pages của bạn vào **Redirect URLs**; thiết lập Site URL là địa chỉ GitHub Pages. Nếu dùng URL Pages trong dạng `https://username.github.io/repo/`, hãy dùng đúng URL đó.

## 2. Deploy Edge Function để Admin mời nhân viên

Cần cài Supabase CLI: https://supabase.com/docs/guides/local-development/cli/getting-started

Trong thư mục dự án:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy invite-user
```

Function sử dụng các biến môi trường Supabase mặc định `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` do Supabase cung cấp. Giữ JWT verification bật (mặc định). Function tự kiểm tra JWT, vai trò Admin và trạng thái tài khoản trước khi gửi lời mời. Supabase Auth cần cấu hình SMTP phù hợp nếu gửi email thật ở quy mô đội nhóm; email mặc định có giới hạn.

**Nhân viên:** Nhận email mời → bấm liên kết → ứng dụng mở phiên đăng nhập → trong thanh bên chọn **Đổi mật khẩu** để đặt mật khẩu mới. Nếu nhà cung cấp email/redirect không tự mở phiên, cần xử lý link mời theo cấu hình Auth; trước khi triển khai thực tế hãy thử toàn bộ luồng bằng tài khoản test. Sau khi có mật khẩu, dùng email + mật khẩu để đăng nhập.

## 3. Triển khai GitHub Pages

1. Tạo repository GitHub (có thể là public; không lưu khóa bí mật).
2. Upload **nội dung** thư mục `team-workspace/` lên gốc repository, đảm bảo `index.html` nằm ở gốc.
3. **Settings → Pages → Build and deployment → Deploy from a branch → main / (root) → Save**.
4. Mở URL Pages, điền Project URL và Publishable key trong màn hình thiết lập (lưu localStorage riêng trên mỗi thiết bị). Sau đó đăng nhập Admin.
5. Nếu bạn cập nhật `sw.js`, hãy đổi tên CACHE từ `team-workspace-v1.0.0` sang số phiên bản mới. Để nhận cập nhật, người dùng tải lại trang khi có Internet.

## 4. Cách dùng

- Admin: Tạo dự án → Mời nhân viên → Giao việc (chọn dự án, nhân viên, hạn) → Theo dõi dashboard → Nghiệm thu hoặc yêu cầu bổ sung.
- Nhân viên: Đăng nhập → Công việc của tôi → Chọn công việc → Báo cáo tiến độ → Điền phần trăm, ngày, ghi chú, trạng thái → Chọn file → Gửi.
- Mỗi lần gửi báo cáo tạo một bản ghi bất biến. Trigger database cập nhật `tasks.progress` và `tasks.status`. Chọn **Đề nghị nghiệm thu** để Admin xem và xác nhận.
- File được lưu trong private bucket, link tải tạm thời có thời hạn 60 giây.
- Trạng thái 100% không tự nghiệm thu. Admin cần bấm **Nghiệm thu**.

## 5. Bảo mật và giới hạn

- **Bắt buộc kiểm thử RLS trước khi sử dụng thực tế.** Test 2 tài khoản nhân viên A/B: A không được xem/sửa việc, báo cáo và file của B; nhân viên không được sửa quyền, công việc, tiến độ trực tiếp; tài khoản bị khóa không được xem dữ liệu. Test thêm các URL Storage trực tiếp.
- Supabase RLS là lớp phân quyền thật; ẩn nút trên giao diện không phải cơ chế bảo mật.
- Khóa tài khoản trong `profiles.active=false` chặn truy cập dữ liệu qua RLS; không nhất thiết thu hồi ngay Auth session. Muốn vô hiệu hóa Auth hoàn toàn, Admin cần xử lý riêng qua Auth Admin API.
- Để tránh upload file mồ côi, bản V1 lưu báo cáo trước rồi tải file sau. Nếu upload lỗi, báo cáo vẫn lưu và hiển thị lỗi file.
- Báo cáo hiển thị tối đa 300 bản ghi gần nhất trong V1; cần pagination nếu có nhiều hơn.
- File tối đa 10MB/file. Các định dạng file được phép phụ thuộc chính sách bucket; với file CAD dung lượng lớn cần điều chỉnh giới hạn, kiểm tra loại file và cân nhắc chi phí Storage.
- Không có gửi email tự động khi báo cáo mới, chưa có xuất Excel và chưa có lưu báo cáo offline. Những tính năng này là phạm vi V1.1.
- Service worker cache frontend; **không cache dữ liệu riêng tư của Supabase**. Khi mất Internet không thể gửi báo cáo.
- Cần cân nhắc chính sách bảo vệ dữ liệu nhân viên, sao lưu database, retention và audit khi vận hành thật.

## 6. Các file

- `index.html`, `style.css`, `app.js`: giao diện và logic frontend.
- `manifest.webmanifest`, `sw.js`, `icon.svg`: PWA.
- `supabase/schema.sql`: bảng, trigger, phân quyền, storage.
- `supabase/functions/invite-user/index.ts`: API mời nhân viên (server-side).

**Lưu ý:** Đây là bộ mã nguồn triển khai V1, chưa được kết nối với Supabase project thực của bạn. Cần cấu hình và kiểm thử end-to-end trên project thật trước khi dùng cho team.
