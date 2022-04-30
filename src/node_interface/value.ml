module type VALUE = sig
  include Map.OrderedType

  val default : t

  (* Used in testing *)
  val random : unit -> t
end
