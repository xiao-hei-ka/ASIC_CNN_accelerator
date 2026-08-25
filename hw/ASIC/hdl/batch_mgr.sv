module batch_mgr
(
    input   logic           gating_clk,
    input   logic           core_rst_n_2,
    input   logic           is_routing,
    input   logic           cpu_men_in_buffer1_valid        ,//内存缓冲区1是否有效
    input   logic   [11:0]  cpu_men_in_buffer1_count        ,//内存缓冲区1数据量
    input   logic           cpu_men_in_buffer2_valid        ,//内存缓冲区2是否有效
    input   logic   [11:0]  cpu_men_in_buffer2_count        ,//内存缓冲区2数据量
    input   logic           is_first_cycle                  ,//这是core主逻辑第一次循环

    output  logic           im_in_buffer_ptr                ,//指示本轮使用的缓冲区，0:缓冲区1，1:缓冲区2
    output  logic [8:0]     im_in_data_ptr                  ,//指示本轮计算从第几个图像开始，从0开始计数。
    output  logic [6:0]     im_in_data_size                 ,//指示本轮计算图像个数,从0开始计数。
    output  logic           im_in_data_valid                ,//指示图像数据是否有效
    output  logic [1:0]     batch_mgr_error_code             //batch管理错误码(组合逻辑)
)


always_comb begin
    batch_mgr_error_code = '0;
    if(im_in_buffer_ptr == 1'b0 && cpu_men_in_buffer1_valid == 1'b0)begin//指针指向缓冲区1，但缓冲区1数据无效
        batch_mgr_error_code[0] <= 1'b1;
    end
    else if(im_in_buffer_ptr == 1'b0 && cpu_men_in_buffer1_valid == 1'b0)begin//指针指向缓冲区2，但缓冲区2数据无效
        batch_mgr_error_code[0] <= 1'b1;
    end
    if(is_first_cycle == 1'b0 && cpu_men_in_buffer1_count <= 12'(im_in_data_ptr))begin//指针所在缓冲区数不够
        batch_mgr_error_code[1] <= 1'b1;
    end
end

always_comb begin
    if(is_routing == 1'b1)begin
        if(is_first_cycle == 1'b1)begin
            if(cpu_men_in_buffer1_count == '0)begin
                im_in_data_valid = 1'b0;
            end
            else begin
                im_in_data_valid = 1'b1;
            end
        end
        else begin
            if(im_in_buffer_ptr == 1'b0)begin
                if(12'(im_in_data_ptr) + 12'(im_in_data_size) + 12'd2 <= cpu_men_in_buffer1_count)begin
                    im_in_data_valid = 1'b1;
                end
                else if(cpu_men_in_buffer2_count != '0)begin
                    im_in_data_valid = 1'b1;
                end
                else begin
                    im_in_data_valid = 1'b0;
                end
            end
            else begin
                if(12'(im_in_data_ptr) + 12'(im_in_data_size) + 12'd2 <= cpu_men_in_buffer2_count)begin
                    im_in_data_valid = 1'b1;
                end
                else if(cpu_men_in_buffer1_count != '0)begin
                    im_in_data_valid = 1'b1;
                end
                else begin
                    im_in_data_valid = 1'b0;
                end
            end
        end
    end
end

always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        im_in_buffer_ptr    <= 1'b0;
        im_in_data_ptr      <= '0;
        im_in_data_size     <= '0;
    end
    else if(is_routing == 1'b1)begin
        if(is_first_cycle == 1'b1)begin
            if(cpu_men_in_buffer1_count == '0)begin
            end
            else if(cpu_men_in_buffer1_count <= 12'd127)begin
                im_in_data_size <= 7'(cpu_men_in_buffer1_count) - 1;
            end
            else begin
                im_in_data_size <= 7'd127;
            end
        end
        else begin
            //当前data_ptr+size：上次计算的最后一个图像编号（从0数）
            //所以data_ptr+size+1：如果不换buffer，下次计算的第一个图像编号（从0数），即新data_ptr
            //所以data_ptr+size+2：如果不换buffer，下次计算的第一个图像编号（从1数）
            //所以data_ptr+size+2 <= cpu_men_in_buffer_count：下次还可以继续使用该buffer计算
            //新data_ptr + 新size + 1 = data_ptr+size+1 + 新size + 1：上次计算的最后一个图像编号（从1数），以此计算新size
            if(im_in_buffer_ptr == 1'b0)begin//当前指针在buffer0
                if(12'(im_in_data_ptr) + 12'(im_in_data_size) + 12'd2 <= cpu_men_in_buffer1_count)begin
                    im_in_data_ptr <= im_in_data_ptr + 9'(im_in_data_size) + 9'b1;
                    if((12'(im_in_data_ptr) + 12'(im_in_data_size) + 12'd1 + 12'd127 + 12'd1) <= cpu_men_in_buffer1_count)begin
                        im_in_data_size <= 7'd127;
                    end
                    else begin
                        im_in_data_size <= cpu_men_in_buffer1_count - 12'(im_in_data_ptr) - 12'(im_in_data_size) - 12'd1 - 12'd1;
                    end
                end
                else if(cpu_men_in_buffer2_count != '0)begin
                    im_in_buffer_ptr <= 1'b1;
                    im_in_data_ptr   <= '0;
                    if(cpu_men_in_buffer2_count <= 12'd127)begin
                        im_in_data_size <= 7'(cpu_men_in_buffer2_count) - 1;
                    end
                    else begin
                        im_in_data_size <= 7'd127
                    end
                end
                else begin
                end
            end
            else begin//当前指针在buffer2
                if(12'(im_in_data_ptr) + 12'(im_in_data_size) + 12'd2 <= cpu_men_in_buffer2_count)begin
                    im_in_data_ptr <= im_in_data_ptr + 9'(im_in_data_size) + 9'b1;
                    if((12'(im_in_data_ptr) + 12'(im_in_data_size) + 12'd1 + 12'd127 + 12'd1) <= cpu_men_in_buffer2_count)begin
                        im_in_data_size <= 7'd127;
                    end
                    else begin
                        im_in_data_size <= cpu_men_in_buffer2_count - 12'(im_in_data_ptr) - 12'(im_in_data_size) - 12'd1 - 12'd1;
                    end
                end
                else if(cpu_men_in_buffer1_count != '0)begin
                    im_in_buffer_ptr <= 1'b1;
                    im_in_data_ptr   <= '0;
                    if(cpu_men_in_buffer1_count <= 12'd127)begin
                        im_in_data_size <= 7'(cpu_men_in_buffer1_count) - 1;
                    end
                    else begin
                        im_in_data_size <= 7'd127
                    end
                end
                else begin
                end
            end
        end
    end
end
endmodule