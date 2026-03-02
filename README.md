"""
Module: power_module
Project: wr-wichit-cominpowerone
Description: จัดการตรรกะการคำนวณและควบคุมพลังงานหลัก
"""

class PowerManager:
    """
    [Class Description]
    คลาสหลักสำหรับบริหารจัดการพลังงานในระบบ wr-wichit-cominpowerone
    รองรับการคำนวณค่าไฟฟ้าและการตรวจสอบสถานะโหลด
    """

    def __init__(self):
        self.project_name = "wr-wichit-cominpowerone"
        self.base_rate = 4.42  # อัตราค่าไฟต่อหน่วย (ตัวอย่าง)

    def calculate_consumption(self, watts, hours):
        """
        [Function Description]
        คำนวณปริมาณการใช้ไฟฟ้า (Units)
        
        Args:
            watts (int): กำลังไฟฟ้า (วัตต์)
            hours (int): จำนวนชั่วโมงที่ใช้งาน
            
        Returns:
            float: จำนวนหน่วย (Unit) ที่ใช้ไป
        """
        # สูตร: (วัตต์ x ชั่วโมง) / 1000
        units = (watts * hours) / 1000
        return units

    def get_cost(self, units):
        """
        [Function Description]
        คำนวณค่าใช้จ่ายตามจำนวนหน่วย
        """
        return units * self.base_rate
        
