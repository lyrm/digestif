type bigstring =
  ( char,
    Bigarray_compat.int8_unsigned_elt,
    Bigarray_compat.c_layout )
  Bigarray_compat.Array1.t

type 'a iter = ('a -> unit) -> unit

type 'a compare = 'a -> 'a -> int

type 'a equal = 'a -> 'a -> bool

type 'a pp = Format.formatter -> 'a -> unit

module Native = Digestif_native
module By = Digestif_by
module Bi = Digestif_bi
module Eq = Digestif_eq
module Hash = Digestif_hash
module Conv = Digestif_conv

let failwith fmt = Format.ksprintf failwith fmt

module type S = sig
  val digest_size : int

  type ctx

  type kind

  type t

  val kind : kind

  val empty : ctx

  val init : unit -> ctx

  val feed_bytes : ctx -> ?off:int -> ?len:int -> Bytes.t -> ctx

  val feed_string : ctx -> ?off:int -> ?len:int -> String.t -> ctx

  val feed_bigstring : ctx -> ?off:int -> ?len:int -> bigstring -> ctx

  val feedi_bytes : ctx -> Bytes.t iter -> ctx

  val feedi_string : ctx -> String.t iter -> ctx

  val feedi_bigstring : ctx -> bigstring iter -> ctx

  val get : ctx -> t

  val digest_bytes : ?off:int -> ?len:int -> Bytes.t -> t

  val digest_string : ?off:int -> ?len:int -> String.t -> t

  val digest_bigstring : ?off:int -> ?len:int -> bigstring -> t

  val digesti_bytes : Bytes.t iter -> t

  val digesti_string : String.t iter -> t

  val digesti_bigstring : bigstring iter -> t

  val digestv_bytes : Bytes.t list -> t

  val digestv_string : String.t list -> t

  val digestv_bigstring : bigstring list -> t

  val hmac_bytes : key:Bytes.t -> ?off:int -> ?len:int -> Bytes.t -> t

  val hmac_string : key:String.t -> ?off:int -> ?len:int -> String.t -> t

  val hmac_bigstring : key:bigstring -> ?off:int -> ?len:int -> bigstring -> t

  val hmaci_bytes : key:Bytes.t -> Bytes.t iter -> t

  val hmaci_string : key:String.t -> String.t iter -> t

  val hmaci_bigstring : key:bigstring -> bigstring iter -> t

  val hmacv_bytes : key:Bytes.t -> Bytes.t list -> t

  val hmacv_string : key:String.t -> String.t list -> t

  val hmacv_bigstring : key:bigstring -> bigstring list -> t

  val unsafe_compare : t compare

  val equal : t equal

  val pp : t pp

  val of_hex : string -> t

  val of_hex_opt : string -> t option

  val consistent_of_hex : string -> t

  val consistent_of_hex_opt : string -> t option

  val to_hex : t -> string

  val of_raw_string : string -> t

  val of_raw_string_opt : string -> t option

  val to_raw_string : t -> string
end

module type MAC = sig
  type t

  val mac_bytes : key:Bytes.t -> ?off:int -> ?len:int -> Bytes.t -> t

  val mac_string : key:String.t -> ?off:int -> ?len:int -> String.t -> t

  val mac_bigstring : key:bigstring -> ?off:int -> ?len:int -> bigstring -> t

  val maci_bytes : key:Bytes.t -> Bytes.t iter -> t

  val maci_string : key:String.t -> String.t iter -> t

  val maci_bigstring : key:bigstring -> bigstring iter -> t

  val macv_bytes : key:Bytes.t -> Bytes.t list -> t

  val macv_string : key:String.t -> String.t list -> t

  val macv_bigstring : key:bigstring -> bigstring list -> t
end

module type Foreign = sig
  open Native

  type kind

  module Bigstring : sig
    val init : ctx -> unit

    val update : ctx -> ba -> int -> int -> unit

    val finalize : ctx -> ba -> int -> unit
  end

  module Bytes : sig
    val init : ctx -> unit

    val update : ctx -> st -> int -> int -> unit

    val finalize : ctx -> st -> int -> unit
  end

  val ctx_size : unit -> int
end

module type Desc = sig
  type kind

  val block_size : int

  val digest_size : int

  val kind : kind
end

module Unsafe (F : Foreign) (D : Desc) = struct
  let block_size = D.block_size

  and digest_size = D.digest_size

  and ctx_size = F.ctx_size ()

  let init () =
    let t = By.create ctx_size in
    F.Bytes.init t ;
    t

  let empty =
    let buf = Bytes.create ctx_size in
    F.Bytes.init buf ;
    buf

  let unsafe_feed_bytes t ?off ?len buf =
    let off, len =
      match (off, len) with
      | Some off, Some len -> (off, len)
      | Some off, None -> (off, By.length buf - off)
      | None, Some len -> (0, len)
      | None, None -> (0, By.length buf) in
    if off < 0 || len < 0 || off > By.length buf - len
    then invalid_arg "offset out of bounds"
    else F.Bytes.update t buf off len

  let unsafe_feed_string t ?off ?len buf =
    unsafe_feed_bytes t ?off ?len (Bytes.unsafe_of_string buf)

  let unsafe_feed_bigstring t ?off ?len buf =
    let off, len =
      match (off, len) with
      | Some off, Some len -> (off, len)
      | Some off, None -> (off, Bi.length buf - off)
      | None, Some len -> (0, len)
      | None, None -> (0, Bi.length buf) in
    if off < 0 || len < 0 || off > Bi.length buf - len
    then invalid_arg "offset out of bounds"
    else F.Bigstring.update t buf off len

  let unsafe_get t =
    let res = By.create digest_size in
    By.fill res 0 digest_size '\000' ;
    F.Bytes.finalize t res 0 ;
    res
end

module Core (F : Foreign) (D : Desc) = struct
  type t = string

  type ctx = Native.ctx

  type kind = F.kind

  include Unsafe (F) (D)
  include Conv.Make (D)
  include Eq.Make (D)

  let kind = D.kind

  let get t =
    let t = Native.dup t in
    unsafe_get t |> By.unsafe_to_string

  let feed_bytes t ?off ?len buf =
    let t = Native.dup t in
    unsafe_feed_bytes t ?off ?len buf ;
    t

  let feed_string t ?off ?len buf =
    let t = Native.dup t in
    unsafe_feed_string t ?off ?len buf ;
    t

  let feed_bigstring t ?off ?len buf =
    let t = Native.dup t in
    unsafe_feed_bigstring t ?off ?len buf ;
    t

  let feedi_bytes t iter =
    let t = Native.dup t in
    let feed buf = unsafe_feed_bytes t buf in
    iter feed ;
    t

  let feedi_string t iter =
    let t = Native.dup t in
    let feed buf = unsafe_feed_string t buf in
    iter feed ;
    t

  let feedi_bigstring t iter =
    let t = Native.dup t in
    let feed buf = unsafe_feed_bigstring t buf in
    iter feed ;
    t

  let digest_bytes ?off ?len buf = feed_bytes empty ?off ?len buf |> get

  let digest_string ?off ?len buf = feed_string empty ?off ?len buf |> get

  let digest_bigstring ?off ?len buf = feed_bigstring empty ?off ?len buf |> get

  let digesti_bytes iter = feedi_bytes empty iter |> get

  let digesti_string iter = feedi_string empty iter |> get

  let digesti_bigstring iter = feedi_bigstring empty iter |> get

  let digestv_bytes lst = digesti_bytes (fun f -> List.iter f lst)

  let digestv_string lst = digesti_string (fun f -> List.iter f lst)

  let digestv_bigstring lst = digesti_bigstring (fun f -> List.iter f lst)
end

module Make (F : Foreign) (D : Desc) = struct
  include Core (F) (D)

  let bytes_opad = By.make block_size '\x5c'

  let bytes_ipad = By.make block_size '\x36'

  let rec norm_bytes key =
    match Stdlib.compare (String.length key) block_size with
    | 1 -> norm_bytes (digest_string key)
    | -1 -> By.rpad (By.unsafe_of_string key) block_size '\000'
    | _ -> By.of_string key

  let bigstring_opad = Bi.init block_size (fun _ -> '\x5c')

  let bigstring_ipad = Bi.init block_size (fun _ -> '\x36')

  let norm_bigstring key =
    let key = Bi.to_string key in
    let res0 = norm_bytes key in
    let res1 = Bi.create (By.length res0) in
    Bi.blit_from_bytes res0 0 res1 0 (By.length res0) ;
    res1

  let hmaci_bytes ~key iter =
    let key = norm_bytes (By.unsafe_to_string key) in
    let outer = Native.XOR.Bytes.xor key bytes_opad in
    let inner = Native.XOR.Bytes.xor key bytes_ipad in
    let res =
      digesti_bytes (fun f ->
          f inner ;
          iter f) in
    digesti_bytes (fun f ->
        f outer ;
        f (By.unsafe_of_string res))

  let hmaci_string ~key iter =
    let key = norm_bytes key in
    (* XXX(dinosaure): safe, [rpad] and [digest] have a read-only access. *)
    let outer = Native.XOR.Bytes.xor key bytes_opad in
    let inner = Native.XOR.Bytes.xor key bytes_ipad in
    let ctx = feed_bytes empty inner in
    let res = feedi_string ctx iter |> get in
    let ctx = feed_bytes empty outer in
    feed_string ctx (res :> string) |> get

  let hmaci_bigstring ~key iter =
    let key = norm_bigstring key in
    let outer = Native.XOR.Bigstring.xor key bigstring_opad in
    let inner = Native.XOR.Bigstring.xor key bigstring_ipad in
    let res =
      digesti_bigstring (fun f ->
          f inner ;
          iter f) in
    let ctx = feed_bigstring empty outer in
    feed_string ctx (res :> string) |> get

  let hmac_bytes ~key ?off ?len buf =
    let buf =
      match (off, len) with
      | Some off, Some len -> By.sub buf off len
      | Some off, None -> By.sub buf off (By.length buf - off)
      | None, Some len -> By.sub buf 0 len
      | None, None -> buf in
    hmaci_bytes ~key (fun f -> f buf)

  let hmac_string ~key ?off ?len buf =
    let buf =
      match (off, len) with
      | Some off, Some len -> String.sub buf off len
      | Some off, None -> String.sub buf off (String.length buf - off)
      | None, Some len -> String.sub buf 0 len
      | None, None -> buf in
    hmaci_string ~key (fun f -> f buf)

  let hmac_bigstring ~key ?off ?len buf =
    let buf =
      match (off, len) with
      | Some off, Some len -> Bi.sub buf off len
      | Some off, None -> Bi.sub buf off (Bi.length buf - off)
      | None, Some len -> Bi.sub buf 0 len
      | None, None -> buf in
    hmaci_bigstring ~key (fun f -> f buf)

  let hmacv_bytes ~key bufs = hmaci_bytes ~key (fun f -> List.iter f bufs)

  let hmacv_string ~key bufs = hmaci_string ~key (fun f -> List.iter f bufs)

  let hmacv_bigstring ~key bufs =
    hmaci_bigstring ~key (fun f -> List.iter f bufs)
end

(* XXX(dinosaure): this interface provide a new function to set digest size and
   key. See #20. *)
module type Foreign_BLAKE2 = sig
  open Native

  type kind

  module Bigstring : sig
    val update : ctx -> ba -> int -> int -> unit

    val finalize : ctx -> ba -> int -> unit

    val with_outlen_and_key : ctx -> int -> ba -> int -> int -> unit
  end

  module Bytes : sig
    val update : ctx -> st -> int -> int -> unit

    val finalize : ctx -> st -> int -> unit

    val with_outlen_and_key : ctx -> int -> st -> int -> int -> unit
  end

  val max_outlen : unit -> int

  val ctx_size : unit -> int

  val key_size : unit -> int
end

module Make_BLAKE2 (F : Foreign_BLAKE2) (D : Desc) = struct
  let () =
    if D.digest_size > F.max_outlen ()
    then
      failwith "Invalid digest_size:%d to make a BLAKE2{S,B} implementation"
        D.digest_size

  include Make
            (struct
              type kind = F.kind

              module Bigstring = struct
                let init ctx =
                  F.Bigstring.with_outlen_and_key ctx D.digest_size Bi.empty 0 0

                let update = F.Bigstring.update

                let finalize = F.Bigstring.finalize
              end

              module Bytes = struct
                let init ctx =
                  F.Bytes.with_outlen_and_key ctx D.digest_size By.empty 0 0

                let update = F.Bytes.update

                let finalize = F.Bytes.finalize
              end

              let ctx_size () = F.ctx_size ()
            end)
            (D)

  type outer = t

  module Keyed = struct
    type t = outer

    let key_size = F.key_size ()

    let maci_bytes ~key iter : t =
      if By.length key > key_size
      then invalid_arg "BLAKE2{S,B}.Keyed.maci_bytes: invalid key" ;
      let ctx = By.create ctx_size in
      F.Bytes.with_outlen_and_key ctx digest_size key 0 (By.length key) ;
      feedi_bytes ctx iter |> get

    let maci_string ~key iter =
      if String.length key > key_size
      then invalid_arg "BLAKE2{S,B}.Keyed.maci_string: invalid key" ;
      let ctx = By.create ctx_size in
      F.Bytes.with_outlen_and_key ctx digest_size (By.unsafe_of_string key) 0
        (String.length key) ;
      feedi_string ctx iter |> get

    let maci_bigstring ~key iter =
      if Bi.length key > key_size
      then invalid_arg "BLAKE2{S,B}.Keyed.maci_bigstring: invalid key" ;
      let ctx = By.create ctx_size in
      F.Bigstring.with_outlen_and_key ctx digest_size key 0 (Bi.length key) ;
      feedi_bigstring ctx iter |> get

    let mac_bytes ~key ?off ?len buf : t =
      let buf =
        match (off, len) with
        | Some off, Some len -> By.sub buf off len
        | Some off, None -> By.sub buf off (By.length buf - off)
        | None, Some len -> By.sub buf 0 len
        | None, None -> buf in
      maci_bytes ~key (fun f -> f buf)

    let mac_string ~key ?off ?len buf =
      let buf =
        match (off, len) with
        | Some off, Some len -> String.sub buf off len
        | Some off, None -> String.sub buf off (String.length buf - off)
        | None, Some len -> String.sub buf 0 len
        | None, None -> buf in
      maci_string ~key (fun f -> f buf)

    let mac_bigstring ~key ?off ?len buf =
      let buf =
        match (off, len) with
        | Some off, Some len -> Bi.sub buf off len
        | Some off, None -> Bi.sub buf off (Bi.length buf - off)
        | None, Some len -> Bi.sub buf 0 len
        | None, None -> buf in
      maci_bigstring ~key (fun f -> f buf)

    let macv_bytes ~key bufs = maci_bytes ~key (fun f -> List.iter f bufs)

    let macv_string ~key bufs = maci_string ~key (fun f -> List.iter f bufs)

    let macv_bigstring ~key bufs =
      maci_bigstring ~key (fun f -> List.iter f bufs)
  end
end

module MD5 : S with type kind = [ `MD5 ] =
  Make
    (Native.MD5)
    (struct
      let digest_size, block_size = (16, 64)

      type kind = [ `MD5 ]

      let kind = `MD5
    end)

module SHA1 : S with type kind = [ `SHA1 ] =
  Make
    (Native.SHA1)
    (struct
      let digest_size, block_size = (20, 64)

      type kind = [ `SHA1 ]

      let kind = `SHA1
    end)

module SHA224 : S with type kind = [ `SHA224 ] =
  Make
    (Native.SHA224)
    (struct
      let digest_size, block_size = (28, 64)

      type kind = [ `SHA224 ]

      let kind = `SHA224
    end)

module SHA256 : S with type kind = [ `SHA256 ] =
  Make
    (Native.SHA256)
    (struct
      let digest_size, block_size = (32, 64)

      type kind = [ `SHA256 ]

      let kind = `SHA256
    end)

module SHA384 : S with type kind = [ `SHA384 ] =
  Make
    (Native.SHA384)
    (struct
      let digest_size, block_size = (48, 128)

      type kind = [ `SHA384 ]

      let kind = `SHA384
    end)

module SHA512 : S with type kind = [ `SHA512 ] =
  Make
    (Native.SHA512)
    (struct
      let digest_size, block_size = (64, 128)

      type kind = [ `SHA512 ]

      let kind = `SHA512
    end)

module WHIRLPOOL : S with type kind = [ `WHIRLPOOL ] =
  Make
    (Native.WHIRLPOOL)
    (struct
      let digest_size, block_size = (64, 64)

      type kind = [ `WHIRLPOOL ]

      let kind = `WHIRLPOOL
    end)

module BLAKE2B : sig
  include S with type kind = [ `BLAKE2B ]

  module Keyed : MAC with type t = t
end =
  Make_BLAKE2
    (Native.BLAKE2B)
    (struct
      let digest_size, block_size = (64, 128)

      type kind = [ `BLAKE2B ]

      let kind = `BLAKE2B
    end)

module BLAKE2S : sig
  include S with type kind = [ `BLAKE2S ]

  module Keyed : MAC with type t = t
end =
  Make_BLAKE2
    (Native.BLAKE2S)
    (struct
      let digest_size, block_size = (32, 64)

      type kind = [ `BLAKE2S ]

      let kind = `BLAKE2S
    end)

module RMD160 : S with type kind = [ `RMD160 ] =
  Make
    (Native.RMD160)
    (struct
      let digest_size, block_size = (20, 64)

      type kind = [ `RMD160 ]

      let kind = `RMD160
    end)

module Make_BLAKE2B (D : sig
  val digest_size : int
end) : S with type kind = [ `BLAKE2B ] = struct
  include Make_BLAKE2
            (Native.BLAKE2B)
            (struct
              let digest_size, block_size = (D.digest_size, 128)

              type kind = [ `BLAKE2B ]

              let kind = `BLAKE2B
            end)
end

module Make_BLAKE2S (D : sig
  val digest_size : int
end) : S with type kind = [ `BLAKE2S ] = struct
  include Make_BLAKE2
            (Native.BLAKE2S)
            (struct
              let digest_size, block_size = (D.digest_size, 64)

              type kind = [ `BLAKE2S ]

              let kind = `BLAKE2S
            end)
end

include Hash

type blake2b = (module S with type kind = [ `BLAKE2B ])

type blake2s = (module S with type kind = [ `BLAKE2S ])

let module_of : type k. k hash -> (module S with type kind = k) =
 fun hash ->
  let b2b : (int, blake2b) Hashtbl.t = Hashtbl.create 13 in
  let b2s : (int, blake2s) Hashtbl.t = Hashtbl.create 13 in
  match hash with
  | MD5 -> (module MD5)
  | SHA1 -> (module SHA1)
  | RMD160 -> (module RMD160)
  | SHA224 -> (module SHA224)
  | SHA256 -> (module SHA256)
  | SHA384 -> (module SHA384)
  | SHA512 -> (module SHA512)
  | WHIRLPOOL -> (module WHIRLPOOL)
  | BLAKE2B digest_size -> (
      match Hashtbl.find b2b digest_size with
      | exception Not_found ->
          let m : (module S with type kind = [ `BLAKE2B ]) =
            (module Make_BLAKE2B (struct
              let digest_size = digest_size
            end) : S
              with type kind = [ `BLAKE2B ]) in
          Hashtbl.replace b2b digest_size m ;
          m
      | m -> m)
  | BLAKE2S digest_size ->
  match Hashtbl.find b2s digest_size with
  | exception Not_found ->
      let m =
        (module Make_BLAKE2S (struct
          let digest_size = digest_size
        end) : S
          with type kind = [ `BLAKE2S ]) in
      Hashtbl.replace b2s digest_size m ;
      m
  | m -> m

type 'kind t = string

let digest_bytes : type k. k hash -> Bytes.t -> k t =
 fun hash buf ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.digest_bytes buf) : H.kind t)

let digest_string : type k. k hash -> String.t -> k t =
 fun hash buf ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.digest_string buf) : H.kind t)

let digest_bigstring : type k. k hash -> bigstring -> k t =
 fun hash buf ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.digest_bigstring buf) : H.kind t)

let digesti_bytes : type k. k hash -> Bytes.t iter -> k t =
 fun hash iter ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.digesti_bytes iter) : H.kind t)

let digesti_string : type k. k hash -> String.t iter -> k t =
 fun hash iter ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.digesti_string iter) : H.kind t)

let digesti_bigstring : type k. k hash -> bigstring iter -> k t =
 fun hash iter ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.digesti_bigstring iter) : H.kind t)

let hmaci_bytes : type k. k hash -> key:Bytes.t -> Bytes.t iter -> k t =
 fun hash ~key iter ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.hmaci_bytes ~key iter) : H.kind t)

let hmaci_string : type k. k hash -> key:String.t -> String.t iter -> k t =
 fun hash ~key iter ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.hmaci_string ~key iter) : H.kind t)

let hmaci_bigstring : type k. k hash -> key:bigstring -> bigstring iter -> k t =
 fun hash ~key iter ->
  let module H = (val module_of hash) in
  (H.to_raw_string (H.hmaci_bigstring ~key iter) : H.kind t)

(* XXX(dinosaure): unsafe part to avoid overhead. *)

let unsafe_compare : type k. k hash -> k t -> k t -> int =
 fun hash a b ->
  let module H = (val module_of hash) in
  let unsafe : 'k t -> H.t = H.of_raw_string in
  H.unsafe_compare (unsafe a) (unsafe b)

let equal : type k. k hash -> k t equal =
 fun hash a b ->
  let module H = (val module_of hash) in
  let unsafe : 'k t -> H.t = H.of_raw_string in
  H.equal (unsafe a) (unsafe b)

let pp : type k. k hash -> k t pp =
 fun hash ppf t ->
  let module H = (val module_of hash) in
  let unsafe : 'k t -> H.t = H.of_raw_string in
  H.pp ppf (unsafe t)

let consistent_of_hex : type k. k hash -> string -> k t =
 fun hash hex ->
  let module H = (val module_of hash) in
  H.to_raw_string (H.consistent_of_hex hex)

let consistent_of_hex_opt : type k. k hash -> string -> k t option =
 fun hash hex ->
  let module H = (val module_of hash) in
  match H.consistent_of_hex_opt hex with
  | None -> None
  | Some digest -> Some (H.to_raw_string digest)

let of_hex : type k. k hash -> string -> k t =
 fun hash hex ->
  let module H = (val module_of hash) in
  H.to_raw_string (H.of_hex hex)

let of_hex_opt : type k. k hash -> string -> k t option =
 fun hash hex ->
  let module H = (val module_of hash) in
  match H.of_hex_opt hex with
  | None -> None
  | Some digest -> Some (H.to_raw_string digest)

let to_hex : type k. k hash -> k t -> string =
 fun hash t ->
  let module H = (val module_of hash) in
  let unsafe : 'k t -> H.t = H.of_raw_string in
  H.to_hex (unsafe t)

let of_raw_string : type k. k hash -> string -> k t =
 fun hash s ->
  let module H = (val module_of hash) in
  let unsafe : H.t -> 'k t = H.to_raw_string in
  unsafe (H.of_raw_string s)

let of_raw_string_opt : type k. k hash -> string -> k t option =
 fun hash s ->
  let module H = (val module_of hash) in
  let unsafe : H.t -> 'k t = H.to_raw_string in
  match H.of_raw_string_opt s with
  | None -> None
  | Some digest -> Some (unsafe digest)

let to_raw_string : type k. k hash -> k t -> string = fun _ t -> t

let of_digest (type hash kind)
    (module H : S with type t = hash and type kind = kind) (hash : H.t) : kind t
    =
  H.to_raw_string hash

let of_md5 hash = of_raw_string md5 (MD5.to_raw_string hash)

let of_sha1 hash = of_raw_string sha1 (SHA1.to_raw_string hash)

let of_rmd160 hash = of_raw_string rmd160 (RMD160.to_raw_string hash)

let of_sha224 hash = of_raw_string sha224 (SHA224.to_raw_string hash)

let of_sha256 hash = of_raw_string sha256 (SHA256.to_raw_string hash)

let of_sha384 hash = of_raw_string sha384 (SHA384.to_raw_string hash)

let of_sha512 hash = of_raw_string sha512 (SHA512.to_raw_string hash)

let of_whirlpool hash = of_raw_string whirlpool (WHIRLPOOL.to_raw_string hash)

let of_blake2b hash =
  of_raw_string (blake2b BLAKE2B.digest_size) (BLAKE2B.to_raw_string hash)

let of_blake2s hash =
  of_raw_string (blake2s BLAKE2S.digest_size) (BLAKE2S.to_raw_string hash)
