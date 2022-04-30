module type VALUE = sig
  include Map.OrderedType

  val default : t
end
