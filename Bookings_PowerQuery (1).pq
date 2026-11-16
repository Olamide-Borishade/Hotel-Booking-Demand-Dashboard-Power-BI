// Bookings query: cleans hotel_bookings.csv for the Power BI dashboard
// Replace the file path in Source with your own before running.
let
    // 1. Load the raw file. Every column arrives as text on purpose.
    Source = Csv.Document(
        File.Contents("C:\Users\game\Downloads\hotel_bookings.csv\hotel_bookings.csv"),
        [Delimiter = ",", Columns = 32, Encoding = 65001, QuoteStyle = QuoteStyle.None]
    ),
    PromotedHeaders = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    // 2. Turn placeholder text into real nulls
    NullText = Table.ReplaceValue(PromotedHeaders, "NULL", null, Replacer.ReplaceValue, {"agent", "company", "country"}),
    NAText = Table.ReplaceValue(NullText, "NA", null, Replacer.ReplaceValue, {"children"}),

    // 3. Set data types (en-US so decimals always read with a dot)
    Typed = Table.TransformColumnTypes(NAText, {
        {"hotel", type text}, {"is_canceled", Int64.Type}, {"lead_time", Int64.Type},
        {"arrival_date_year", Int64.Type}, {"arrival_date_month", type text},
        {"arrival_date_week_number", Int64.Type}, {"arrival_date_day_of_month", Int64.Type},
        {"stays_in_weekend_nights", Int64.Type}, {"stays_in_week_nights", Int64.Type},
        {"adults", Int64.Type}, {"children", Int64.Type}, {"babies", Int64.Type},
        {"meal", type text}, {"country", type text}, {"market_segment", type text},
        {"distribution_channel", type text}, {"is_repeated_guest", Int64.Type},
        {"previous_cancellations", Int64.Type}, {"previous_bookings_not_canceled", Int64.Type},
        {"reserved_room_type", type text}, {"assigned_room_type", type text},
        {"booking_changes", Int64.Type}, {"deposit_type", type text},
        {"agent", type text}, {"company", type text}, {"days_in_waiting_list", Int64.Type},
        {"customer_type", type text}, {"adr", Currency.Type},
        {"required_car_parking_spaces", Int64.Type}, {"total_of_special_requests", Int64.Type},
        {"reservation_status", type text}, {"reservation_status_date", type date}
    }, "en-US"),

    // 4. Fill blanks with meaning
    ChildrenZero = Table.ReplaceValue(Typed, null, 0, Replacer.ReplaceValue, {"children"}),
    CountryFilled = Table.ReplaceValue(ChildrenZero, null, "Unknown", Replacer.ReplaceValue, {"country"}),
    AgentFilled = Table.ReplaceValue(CountryFilled, null, "None", Replacer.ReplaceValue, {"agent"}),

    // 5. Readable meal labels (SC and Undefined both mean no meal package)
    MealLabels = Table.TransformColumns(AgentFilled, {{"meal", each
        if _ = "BB" then "Bed & Breakfast"
        else if _ = "HB" then "Half Board"
        else if _ = "FB" then "Full Board"
        else "No Meal Package", type text}}),

    // 6. Build one real Arrival Date from the three arrival columns
    MonthNames = {"January", "February", "March", "April", "May", "June",
                  "July", "August", "September", "October", "November", "December"},
    AddArrivalDate = Table.AddColumn(MealLabels, "Arrival Date", each
        #date([arrival_date_year], List.PositionOf(MonthNames, [arrival_date_month]) + 1, [arrival_date_day_of_month]),
        type date),

    // 7. Helper columns (fixed facts about each booking)
    AddNights = Table.AddColumn(AddArrivalDate, "Total Nights", each [stays_in_weekend_nights] + [stays_in_week_nights], Int64.Type),
    AddGuests = Table.AddColumn(AddNights, "Total Guests", each [adults] + [children] + [babies], Int64.Type),
    AddPartyType = Table.AddColumn(AddGuests, "Party Type", each if [children] + [babies] > 0 then "Family" else "Adults Only", type text),
    AddGuestStatus = Table.AddColumn(AddPartyType, "Guest Status", each if [is_repeated_guest] = 1 then "Repeat Guest" else "New Guest", type text),
    AddLeadBand = Table.AddColumn(AddGuestStatus, "Lead Time Band", each
        if [lead_time] <= 7 then "0-7 days"
        else if [lead_time] <= 30 then "8-30 days"
        else if [lead_time] <= 90 then "31-90 days"
        else if [lead_time] <= 180 then "91-180 days"
        else if [lead_time] <= 365 then "181-365 days"
        else "Over 365 days", type text),
    AddLeadOrder = Table.AddColumn(AddLeadBand, "Lead Time Band Order", each
        if [lead_time] <= 7 then 1
        else if [lead_time] <= 30 then 2
        else if [lead_time] <= 90 then 3
        else if [lead_time] <= 180 then 4
        else if [lead_time] <= 365 then 5
        else 6, Int64.Type),

    // 8. Remove invalid rows: negative ADR, the 5,400 outlier, bookings with no guests
    //    (to drop duplicate rows, add: Deduped = Table.Distinct(ValidRows), and use Deduped below)
    ValidRows = Table.SelectRows(AddLeadOrder, each [adr] >= 0 and [adr] <= 1000 and [Total Guests] > 0),

    // 9. Surrogate key, drop unused columns, readable names
    AddBookingID = Table.AddIndexColumn(ValidRows, "Booking ID", 1, 1, Int64.Type),
    RemovedCols = Table.RemoveColumns(AddBookingID, {"company", "arrival_date_year", "arrival_date_month",
                                                     "arrival_date_week_number", "arrival_date_day_of_month"}),
    Renamed = Table.RenameColumns(RemovedCols, {
        {"hotel", "Hotel"}, {"is_canceled", "Is Canceled"}, {"lead_time", "Lead Time (Days)"},
        {"stays_in_weekend_nights", "Weekend Nights"}, {"stays_in_week_nights", "Week Nights"},
        {"adults", "Adults"}, {"children", "Children"}, {"babies", "Babies"},
        {"meal", "Meal Plan"}, {"country", "Country"}, {"market_segment", "Market Segment"},
        {"distribution_channel", "Distribution Channel"}, {"is_repeated_guest", "Is Repeat Guest"},
        {"previous_cancellations", "Previous Cancellations"},
        {"previous_bookings_not_canceled", "Previous Bookings Kept"},
        {"reserved_room_type", "Reserved Room Type"}, {"assigned_room_type", "Assigned Room Type"},
        {"booking_changes", "Booking Changes"}, {"deposit_type", "Deposit Type"},
        {"agent", "Agent ID"}, {"days_in_waiting_list", "Days on Waiting List"},
        {"customer_type", "Customer Type"}, {"adr", "ADR"},
        {"required_car_parking_spaces", "Parking Spaces"},
        {"total_of_special_requests", "Special Requests"},
        {"reservation_status", "Reservation Status"}, {"reservation_status_date", "Status Date"}
    })
in
    Renamed
