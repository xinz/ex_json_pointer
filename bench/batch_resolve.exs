doc = %{
  "a" => %{
    "b" => %{
      "c" => [1, 2, %{"d" => "target1"}],
      "e" => "target2"
    },
    "f" => [10, 20, 30, 40]
  },
  "x" => %{
    "y" => %{
      "z" => "target3"
    }
  }
}

large_doc =
  Enum.reduce(1..1000, %{}, fn i, acc ->
    Map.put(acc, "key_#{i}", %{
      "nested_1" => %{
        "nested_2" => [i, i * 2, %{"target" => "val_#{i}"}]
      }
    })
  end)

shared_prefix_doc = %{
  "users" =>
    Enum.into(1..100, %{}, fn i ->
      {
        Integer.to_string(i),
        %{
          "profile" => %{
            "name" => "user_#{i}",
            "email" => "user_#{i}@example.com"
          },
          "settings" => %{
            "theme" => if(rem(i, 2) == 0, do: "dark", else: "light"),
            "locale" => "en"
          },
          "posts" => %{
            "0" => %{"title" => "title_#{i}", "published" => true},
            "1" => %{"title" => "draft_#{i}", "published" => false}
          }
        }
      }
    end)
}

pointers_small = [
  "/a/b/c/2/d",
  "/a/b/e",
  "/a/f/2",
  "/x/y/z",
  "/not/found/path"
]

pointers_large =
  Enum.map(1..100, fn i ->
    "/key_#{i}/nested_1/nested_2/2/target"
  end) ++ ["/key_999/not/found"]

pointers_shared_prefix =
  Enum.flat_map(1..25, fn i ->
    user = Integer.to_string(i)

    [
      "/users/#{user}/profile/name",
      "/users/#{user}/profile/email",
      "/users/#{user}/settings/theme",
      "/users/#{user}/posts/0/title"
    ]
  end) ++ ["/users/999/profile/name"]

Benchee.run(
  %{
    "Enum.into & resolve/2" => fn {d, p} ->
      Enum.into(p, %{}, fn ptr -> {ptr, ExJSONPointer.resolve(d, ptr)} end)
    end,
    "group by first token" => fn {d, p} ->
      grouped =
        Enum.group_by(p, fn ptr ->
          case String.split(ptr, "/", trim: true) do
            [first | _] -> first
            [] -> ""
          end
        end)

      Enum.reduce(grouped, %{}, fn {_first, pointers}, acc ->
        Enum.reduce(pointers, acc, fn ptr, inner_acc ->
          Map.put(inner_acc, ptr, ExJSONPointer.resolve(d, ptr))
        end)
      end)
    end,
    "batch_resolve/2" => fn {d, p} ->
      ExJSONPointer.batch_resolve(d, p)
    end
  },
  inputs: %{
    "Small Doc & Few Pointers" => {doc, pointers_small},
    "Large Doc & Many Pointers" => {large_doc, pointers_large},
    "Shared Prefix Doc & Many Pointers" => {shared_prefix_doc, pointers_shared_prefix}
  },
  time: 3,
  memory_time: 2
)
