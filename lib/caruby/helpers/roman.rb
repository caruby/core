class String
  # @return [Integer] the integer equivalent of this roman numeral
  # @raise ArgumentError if this String is not a roman numeral in the range I-X
  def to_arabic
    case self
      when /^(I{0,3})$/ then $1.size
      when /^(I{0,3})(V|X)$/ then ROMAN_UNITS[$2] - $1.size
      when /^(V)(I{0,3})$/ then ROMAN_UNITS[$1] + $2.size
      else CaRuby.fail(ArgumentError, "#{self} is not a roman numeral in the range I-X")
    end
  end
  
  private
  
  ROMAN_UNITS = {'I' => 1, 'V' => 5, 'X' => 10}
end

class Integer
  # @return [String] the roman numeral equivalent of this integer
  def to_roman
    if self < 1 or self > 10 then CaRuby.fail(ArgumentError, "#{self} cannot be converted to a roman numeral in the range I-X")
    elsif self < 4 then 'I' * self
    elsif self < 6 then ('I' * (5 - self)) + 'V'
    elsif self < 9 then 'V' + ('I' * (self - 5))
    else ('I' * (10 - self)) + 'X'
    end
  end
end