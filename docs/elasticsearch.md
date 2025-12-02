# Elasticsearch 

## Phần 1. Nền tảng kiến trúc phân tán

### 1.1. Giải phẫu vai trò của Node (Node Roles)



### 1.2. Cơ chế Sharding và Replication
Sharding là đơn vị cơ bản để Elasticsearch thực hiện việc chia nhỏ dữ liệu và mở rộng theo chiều ngang (scale-out). 
Mỗi index thực chất là một tập hợp logic của các Shard, và mỗi Shard là một Lucene Index vật lý độc lập:

**Primary Shard và chiến lược Routing**: Mỗi document khi được đưa vào Elasticsearch sẽ được định tuyến đến một Primary Shard cụ thể dựa trên công thức băm nhất quán (consistents hashing). 
```aiignore
shard = hash(routing) (mod number_of_primary_shards)
```
Giá trị `routing` mặc định là `_id` của document. Công thức này giải thích tại sao số lượng Primary Shard là tĩnh và không thể thay đổi sau khi tạo index (trừ khi sử dụng Split API hoặc Reindex), đặt ra yêu cầu
khắt khe về việc quy hoạch dung lượng (capacity planning) ngay từ đầu. Một Primary Sharrd quá lớn (vài trăm GB) sẽ khiến việc recover và rebalancing trở nên cực kỳ chậm chạp, trong khi quá nhiều schard nhỏ (oversharding) 
lại tiêu tốn tài nguyên quản lý (overhead) và làm chậm quá trình tìm kiếm. 

**Replica shard - Đảm bảo tính sẵn sàng và hiệu năng:** Khác với Primary Shard, Replica Shaard là các bản sao chép đầy đủ dữ liệu, phục vụ hai mục đích: đảm bảo High Availability (HA) khi Primary node gặp sự cố, và 
tăng thông lượng đọc (Read Throughput) bằng cách phân tán các search request. Số lượng Replica có thể thay đổi động (dynamic) bất cứ lúc nào để đáp ứng nhu cầu tải đọc thay đổi, tuy nhiên việc tăng Replica cũng đồng nghĩa với việc tăng dung
lương lưu trữ và chi phí CPU/Disk cho việc index dữ liệu (mỗi document phải được index lại trên replica). 

## Phần 2. Core Concepts - Cơ chế nội tại (Internals)

Để tối ưu hoá hiệu năng, Data Engineer cần thấu hiểu vòng đời của dữ liệu từ khi được ghi vào bộ nhớ đệm cho đến khi nằm an toàn trên dĩa cứng, cũng như cơ chế đồng thuận giúp cluster duy trì trạng thái nhất quán. 


### 2.1. Lucene Segments và tính bất biến (Immutability)

Bên trong mỗi Shard, dữ liệu được tổ chức thành các **Segment**. Một đặc điểm cốt lõi của Lucene là các segment này là bất biến (immutable). 
Điều này mang lại lợi ích to lớn về hiệu năng đọc (không cần lock phức tạp) và khả năng cache, nhưng lại đặt ra thách thức cho các thao tác cập nhật (update). 

Khi một document được cập nhật (update) hoặc xoá (delete), Elasticsearch không thực sử sửa đổi dữ liệu trong segment cũ. Thay vào đó:
* **Update:** Document cũ được đánh dấu là "đã xoá" trong một file bitmap đặc biệt (.del file), và phiên bản mới của document được ghi vào một segment hoàn toàn mới. 
* **Delete:** Document chỉ đơn giản được đánh dấu trong file .del. 

Hệ quả của cơ chế này là dung lượng lưu trữ sẽ tăng lên nhanh chóng nếu có nhiều thao tác update/delete. 
Quá trình **Segment Merging** chạy ngầm định kỳ sẽ hợp nhất các segment nhỏ thành các segment lớn hớn và loại bỏ thực sự các document đã bị đánh dấu xoá, giúp giải phóng dung lượng đĩa. 


### 2.2. Near Real-Time (NRT) và Transaction Log
Elasticsearch được gọi là "Gần thời gian thực" vì có một độ trễ nhỏ (mặc định 1 giây) giữa thời điểm index và thời điểm document có thể tìm kiếm được. Quá trình này được kiểm soát bởi cơ chế **Refresh** và **Flush**

1. **Refresh:** Dữ liệu mới được index ban đầu nằm trong In-memory buffer. Mỗi giây (mặc định), tiến trình refresh sẽ sao chép dữ liệu từ buffer này tạo thành một Segment mới. 
Segment này tuy chưa được `fsync` xuống đĩa cứng (vẫn nằm trong file System Cache của OS) nhưng đã có thể mở để tìm kiếm. Đây là lý do tại sao thay đổi không xuất hiện ngay lập tức. 
2. **Translog (Transaction Log):** Để đảm bảo độ bền dữ liệu (Durability) trong trường hợp node bị crash khi segment vẫn chỉ nằm trên RAM, mọi thao tác ghi đều được viết song song vào Translog. 
3. **Flush:** Khi Translog quá lớn hoặc sau một khoảng thời gian (30 phút), quá trình Flush diễn ra: thực hiện `fsync` tất cả segment xuống đĩa cứng và xoá Translog cũ. 

### 2.3. Đồng thuận phân tán: Zen Discovery và Raft

Trước phiên bản 7.0, Elasticsearch sử dụng cơ chế đồng thuận riêng gọi là "Zen Discovery", thường gặp vấn đề "Split-Brain" nếu cấu hình `minimun_master_nodes` sai. Từ phiên bản 7.0 trở đi, Elasticsearch đã cải tiến layer điều phối
cluster (Cluster Coordination) bằng một thuật toán dựa trên Raft nhưng được tinh chỉnh. Khác với Raft tiêu chuẩn (dựa trên Log operation), Elasticsearch tập trung vào việc quản lý Cluster State:
* **Voting Configuration:** Hệ thống tự động quản lý danh sách các node có quyền bầu chọn (voting configuration), loại bỏ gánh nặng cấu hình thủ công `minimum_master_nodes`. Điều này giúp cluster an toàn hơn trước các sự cố mạng phân vùng (network partition).
* **Sequence IDs & Global Checkpoints:** Để đảm bảo tính nhất quán dữ liệu giữa Primary và Replica, Elasticsearch sử dụng Sequence IDs (số thứ tự tăng dần cho mỗi operation trên shard). 
Replica sử dụng Global Checkpoint để biết mình đã đồng bộ đến đâu, giúp quá trình phục hồi (recovery) diễn ra cực nhanh bằng cách chỉ sao chép các operation bị thiếu (delta) thay vì toàn bộ file segment. 

## Phần 3. Indexing Strategies - Chiến lược đánh chỉ mục nâng cao
Một chiến lược Indexing kém cỏi là nguyên nhân hàng đầu dẫn đến hiệu năng search tối tệ và lãng phí tài nguyên. Đối với tiếng Việt, thách thức này càng lớn hơn do đặc thù ngôn ngữ.

### 3.1. Mapping: Dynamic vs Explicit
Mặc dù tính năng **Dynamic Mapping** cho phép Elasticsearch tự động phát hiện và tạo kiểu dữ liệu, nhưng trong môi trường Production, đây thường là nguồn gốc của các rủi ro như "Mapping Explosion" (bùng nổ số lượng field). 
Ví dụ, một object JSON có thể chứa hàng nghìn key ngẫu nhiên, khiến Cluster State phình to và làm chậm Master node. 

**Khuyến nghị:** Luôn sử dụng **Explicit Mapping** (định nghĩa rõ ràng) cho các index production:

* Phân biệt rạch ròi giữa keywword (cho filter, aggregation chính xác) và text (cho full-text search). 
* Sử dụng `date_detection: false` để tránh việc parse nhầm các chuỗi số ngày thành ngày tháng. 

### 3.2. 



### 3.3. 



### 3.4. Tối ưu hóa tốc độ Bulk Indexing
Khi cần nạp lượng lớn dữ liệu (ví dụ: migrate dữ liệu cũ hoặc log stream tốc độ cao), các tham số mặc định sẽ kìm hãm tốc độ. 
* **Tắt refresh:** Thiết lập `refresh_interval: -1` trong quá trình import. Điều này ngăn việc tạo ra quá nhiều segment nhỏ, giảm áp lực merge. 
* **Tăng index buffer:** Tăng `indices.memory.index.buffer_size` lên 20% hoặc 30% ehap (mặc định 10%) để chứa nhiều doc hơn trước khi flush. 
* **Vô hiệu hoá replica:** Tạm thời set `number_of_replica: 0`. Sau khi import xong mới bật lại. Việc để Elasticsearch nhân bản segment file (file-based recovery) nhanh hơn nhiều so với việc index document lặp lại trên từng replica. 



## Phần 4. Data Modeling - Mô hình háo dữ liệu NoSQL

Elasticsearch là cơ sở dữ liệu hướng document (Document-oriented), không hỗ trợ quan hệ (join) theo cách RDBMS. Việc cố ép tư duy chuẩn hoá (Normalization) vào Elasticsearch là sai lầm phổ biến nhất. 

### 4.1. Denormalization (phi chuẩn hoá)
Kỹ thuật tối ưu nhất trong Elasticsearch là **Denormalization**. Thay vì lưu User và Order ở hai index riêng biệt và join khi query, ta lưu thông tin `User` (tên, email) ngay bên trong document `Oder`.
* **Lợi ích:** Tốc độ truy vấn cực nhanh vì chỉ cần đọc một document duy nhất.
* **Đánh đổi:** Dư thừa dữ liệu và phức tạp khi cập nhật (phải update hàng loại document) khi thông tin user thay đổi. Tuy nhiên, trong bài toán Search, ưu tiên tốc độ đọc (read) là số 1. 


### 4.2. Nested Objects vs. Parent Child

Khi bắt buộc phải mô hình hoá quan hệ 1-N (ví dụ: sản phẩm và biến thể, bài viết và comment), ta có hai lựa chọn: 

**Bảng 2: So sánh Nested Object và Parent-Child**




**Chiến lược Flattening:** Một kỹ thuật khác là làm phẳng dữ liệu (Flatenning) sử dụng dấu chấm (Dot notation) như `user.address.city`. Cách này đơn giản, hiệu năng cao như Denormalization nhưng mất khả 
năng query chính xác từng object độc lập trong mảng (cross-object matching). 

## Phần 5. Scaling & Architecture - Chiến lược mở rộng hệ thống
Scaling không chỉ làm thêm phần cứng, mà là quản lý vòng đời dữ liệu thông minh để tối ưu chi phí trên hiệu năng (cost/performance). 

### 5.1. Kiến trúc Hot-Warm-Cold-Frozen


### 5.2. 












